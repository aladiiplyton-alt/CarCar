#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
mod api;
use api::{Chunk, Message, Settings};
use std::{
    path::{Path, PathBuf},
    sync::Mutex,
    time::Duration,
};
use tauri::{Manager, WebviewUrl, WebviewWindowBuilder};
use tokio_util::sync::CancellationToken;
use zeroize::{Zeroize, Zeroizing};

#[derive(Default)]
struct Requests(Mutex<Option<CancellationToken>>);
#[tauri::command]
fn load_settings() -> Settings {
    let mut s = Settings::default();
    // Read only an explicitly adjacent private configuration, never a working-directory file.
    if let Ok(exe) = std::env::current_exe() {
        if let Some(parent) = exe.parent() {
            let path = parent.join("carcar.local.env");
            read_config(&path, &mut s);
        }
    }
    if let Some(path) = std::env::var_os("CARCAR_CONFIG") {
        read_config(&PathBuf::from(path), &mut s)
    }
    if let Ok(v) = std::env::var("CARCAR_API_KEY") {
        s.api_key = v
    }
    if let Ok(v) = std::env::var("CARCAR_BASE_URL") {
        s.base_url = v
    }
    if let Ok(v) = std::env::var("CARCAR_MODEL") {
        s.model = v
    }
    s
}
fn read_config(path: &Path, s: &mut Settings) {
    if let Ok(text) = std::fs::read_to_string(path) {
        let text = Zeroizing::new(text);
        for line in text.lines() {
            if let Some((k, v)) = line.trim_start_matches('\u{feff}').split_once('=') {
                let v = v.trim().to_string();
                match k.trim() {
                    "CARCAR_API_KEY" => s.api_key = v,
                    "CARCAR_BASE_URL" => s.base_url = v,
                    "CARCAR_MODEL" => s.model = v,
                    _ => {}
                }
            }
        }
    }
}
#[tauri::command]
async fn generate(
    state: tauri::State<'_, Requests>,
    settings: Settings,
    messages: Vec<Message>,
    on_event: tauri::ipc::Channel<Chunk>,
) -> Result<(), String> {
    let token = CancellationToken::new();
    {
        let mut current = state.0.lock().map_err(|_| "Ошибка состояния запроса.")?;
        if current.is_some() {
            return Err("Дождитесь завершения текущего запроса.".into());
        }
        *current = Some(token.clone());
    }
    let result = tokio::select! {biased;_=token.cancelled()=>Err("Генерация остановлена.".into()),r=api::request(settings,messages,token.clone(),|text|on_event.send(Chunk{text}).map_err(|_|"Окно приложения закрыто.".into()))=>r};
    if let Ok(mut current) = state.0.lock() {
        *current = None
    }
    result
}
#[tauri::command]
fn cancel_generation(state: tauri::State<'_, Requests>) {
    if let Ok(current) = state.0.lock() {
        if let Some(token) = current.as_ref() {
            token.cancel()
        }
    }
}
#[tauri::command]
fn copy_text(mut text: String) -> Result<(), String> {
    let result = arboard::Clipboard::new()
        .and_then(|mut c| c.set_text(&text))
        .map_err(|_| "Не удалось открыть буфер обмена Windows.".to_string());
    text.zeroize();
    result
}
#[tauri::command]
fn close_app(app: tauri::AppHandle, state: tauri::State<'_, Requests>) {
    cancel_generation(state);
    app.exit(0)
}

fn profiles_root() -> PathBuf {
    std::env::temp_dir().join("CarCar").join("profiles")
}
fn safe_profile(path: &Path) -> bool {
    path.parent() == Some(profiles_root().as_path())
        && path
            .file_name()
            .and_then(|s| s.to_str())
            .is_some_and(|s| uuid::Uuid::parse_str(s).is_ok())
        && !std::fs::symlink_metadata(path).is_ok_and(|m| m.file_type().is_symlink())
}
fn cleanup(path: &Path) {
    if !safe_profile(path) {
        return;
    }
    for _ in 0..80 {
        if !path.exists() || std::fs::remove_dir_all(path).is_ok() {
            return;
        }
        std::thread::sleep(Duration::from_millis(250));
    }
}
#[cfg(windows)]
fn wait_pid(pid: u32) {
    unsafe {
        use windows_sys::Win32::{
            Foundation::CloseHandle,
            System::Threading::{OpenProcess, WaitForSingleObject, PROCESS_SYNCHRONIZE},
        };
        let handle = OpenProcess(PROCESS_SYNCHRONIZE, 0, pid);
        if !handle.is_null() {
            WaitForSingleObject(handle, u32::MAX);
            CloseHandle(handle);
        }
    }
}
#[cfg(not(windows))]
fn wait_pid(_: u32) {}
fn spawn_cleaner(path: &Path) {
    if let Ok(exe) = std::env::current_exe() {
        let mut cmd = std::process::Command::new(exe);
        cmd.arg("--clean-profile")
            .arg(std::process::id().to_string())
            .arg(path);
        #[cfg(windows)]
        {
            use std::os::windows::process::CommandExt;
            cmd.creation_flags(0x08000000);
        }
        let _ = cmd.spawn();
    }
}
fn clean_stale() {
    let root = profiles_root();
    let _ = std::fs::create_dir_all(&root);
    if let Ok(entries) = std::fs::read_dir(root) {
        for e in entries.flatten() {
            let path = e.path();
            if !safe_profile(&path) {
                continue;
            }
            let pid = std::fs::read_to_string(path.join("owner.pid"))
                .ok()
                .and_then(|s| s.parse::<u32>().ok());
            if pid.is_some_and(process_alive) {
                continue;
            }
            cleanup(&path)
        }
    }
}
#[cfg(windows)]
fn process_alive(pid: u32) -> bool {
    unsafe {
        use windows_sys::Win32::{
            Foundation::{CloseHandle, WAIT_TIMEOUT},
            System::Threading::{OpenProcess, WaitForSingleObject, PROCESS_SYNCHRONIZE},
        };
        let h = OpenProcess(PROCESS_SYNCHRONIZE, 0, pid);
        if h.is_null() {
            return false;
        }
        let alive = WaitForSingleObject(h, 0) == WAIT_TIMEOUT;
        CloseHandle(h);
        alive
    }
}
#[cfg(not(windows))]
fn process_alive(_: u32) -> bool {
    false
}
fn main() {
    let args: Vec<_> = std::env::args_os().collect();
    if args.get(1).is_some_and(|a| a == "--clean-profile") {
        if let (Some(pid), Some(path)) = (
            args.get(2)
                .and_then(|s| s.to_str())
                .and_then(|s| s.parse().ok()),
            args.get(3),
        ) {
            let path = PathBuf::from(path);
            if safe_profile(&path) {
                wait_pid(pid);
                cleanup(&path)
            }
        }
        return;
    }
    clean_stale();
    let profile = profiles_root().join(uuid::Uuid::new_v4().to_string());
    if std::fs::create_dir_all(&profile).is_err() {
        return;
    }
    let _ = std::fs::write(profile.join("owner.pid"), std::process::id().to_string());
    spawn_cleaner(&profile);
    let window_profile = profile.clone();
    let app = tauri::Builder::default()
        .manage(Requests::default())
        .invoke_handler(tauri::generate_handler![
            load_settings,
            generate,
            cancel_generation,
            copy_text,
            close_app
        ])
        .setup(move |app| {
            let window = WebviewWindowBuilder::new(app, "main", WebviewUrl::default())
                .title("CarCar")
                .inner_size(600.0, 710.0)
                .min_inner_size(390.0, 470.0)
                .center()
                .decorations(false)
                .shadow(true)
                .incognito(true)
                .disable_drag_drop_handler()
                .on_navigation(|url| {
                    matches!(url.scheme(), "tauri" | "http" | "https")
                        && matches!(
                            url.host_str(),
                            Some("tauri.localhost" | "localhost" | "127.0.0.1")
                        )
                })
                .devtools(cfg!(debug_assertions));
            #[cfg(windows)]
            let window = window.data_directory(window_profile);
            // Explicit test build only; production releases never open a debug port.
            #[cfg(all(windows, feature = "ui-test"))]
            let window = window.additional_browser_args("--remote-debugging-port=19347");
            window.build()?;
            Ok(())
        })
        .build(tauri::generate_context!());
    match app {
        Ok(app) => app.run(|handle, event| {
            if matches!(
                event,
                tauri::RunEvent::ExitRequested { .. } | tauri::RunEvent::Exit
            ) {
                cancel_generation(handle.state::<Requests>());
            }
        }),
        Err(_) => {
            #[cfg(windows)]
            unsafe {
                use windows_sys::Win32::UI::WindowsAndMessaging::{
                    MessageBoxW, MB_ICONERROR, MB_OK,
                };
                let text:Vec<u16>="Не удалось открыть CarCar. Проверьте наличие Microsoft WebView2 Runtime: https://developer.microsoft.com/microsoft-edge/webview2/\0".encode_utf16().collect();
                let title: Vec<u16> = "CarCar\0".encode_utf16().collect();
                MessageBoxW(
                    std::ptr::null_mut(),
                    text.as_ptr(),
                    title.as_ptr(),
                    MB_OK | MB_ICONERROR,
                );
            }
        }
    }
    cleanup(&profile);
}
