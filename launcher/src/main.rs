use reqwest::blocking::Client;
use sha2::{Digest, Sha256};
use std::{
    fs,
    io::{Read, Write},
    path::{Path, PathBuf},
    process::Command,
    time::Duration,
};

fn root() -> PathBuf {
    std::env::temp_dir().join("CarCar").join("runs")
}
fn safe(path: &Path) -> bool {
    path.parent() == Some(root().as_path())
        && path
            .file_name()
            .and_then(|p| p.to_str())
            .is_some_and(|p| uuid::Uuid::parse_str(p).is_ok())
        && !fs::symlink_metadata(path).is_ok_and(|m| m.file_type().is_symlink())
}
fn cleanup(path: &Path) -> bool {
    if !safe(path) {
        return false;
    }
    for _ in 0..80 {
        if !path.exists() || fs::remove_dir_all(path).is_ok() {
            return true;
        }
        std::thread::sleep(Duration::from_millis(250));
    }
    false
}
#[cfg(windows)]
fn alive(pid: u32) -> bool {
    unsafe {
        use windows_sys::Win32::{
            Foundation::{CloseHandle, WAIT_TIMEOUT},
            System::Threading::{OpenProcess, WaitForSingleObject, PROCESS_SYNCHRONIZE},
        };
        let h = OpenProcess(PROCESS_SYNCHRONIZE, 0, pid);
        if h.is_null() {
            return false;
        }
        let live = WaitForSingleObject(h, 0) == WAIT_TIMEOUT;
        CloseHandle(h);
        live
    }
}
#[cfg(not(windows))]
fn alive(_: u32) -> bool {
    false
}
fn stale() {
    let _ = fs::create_dir_all(root());
    if let Ok(entries) = fs::read_dir(root()) {
        for entry in entries.flatten() {
            let path = entry.path();
            if !safe(&path) {
                continue;
            }
            let active = ["owner.pid", "app.pid"].iter().any(|file| {
                fs::read_to_string(path.join(file))
                    .ok()
                    .and_then(|s| s.parse::<u32>().ok())
                    .is_some_and(alive)
            });
            if active {
                continue;
            }
            cleanup(&path);
        }
    }
}
fn webview_present() -> bool {
    // The runtime directory is stable across EdgeUpdate registrations.
    for var in ["ProgramFiles(x86)", "ProgramFiles", "LOCALAPPDATA"] {
        if let Some(base) = std::env::var_os(var) {
            let folder = PathBuf::from(base).join("Microsoft/EdgeWebView/Application");
            if fs::read_dir(folder).is_ok_and(|it| {
                it.flatten()
                    .any(|e| e.path().join("msedgewebview2.exe").is_file())
            }) {
                return true;
            }
        }
    }
    false
}
fn ensure_webview() -> Result<(), String> {
    if webview_present() {
        return Ok(());
    }
    println!(
        "Для CarCar нужен Microsoft WebView2 Runtime. Открыть официальный сайт установки? [Y/N]"
    );
    let mut input = String::new();
    std::io::stdin()
        .read_line(&mut input)
        .map_err(|_| "Не удалось прочитать ответ.")?;
    if input.trim().eq_ignore_ascii_case("y") {
        Command::new("rundll32.exe")
            .args([
                "url.dll,FileProtocolHandler",
                "https://developer.microsoft.com/microsoft-edge/webview2/",
            ])
            .spawn()
            .map_err(|_| "Не удалось открыть сайт Microsoft.")?;
    }
    Err("Установите WebView2 Runtime с сайта Microsoft и запустите carcar ещё раз.".into())
}
fn download(client: &Client, url: &str, dest: &Path, max: u64) -> Result<(), String> {
    let mut parsed = reqwest::Url::parse(url).map_err(|_| "Неверный URL загрузки.")?;
    if parsed.scheme() != "https" {
        return Err("Загрузка разрешена только через HTTPS.".into());
    }
    parsed
        .query_pairs_mut()
        .append_pair("carcar", &uuid::Uuid::new_v4().to_string());
    let mut response = client
        .get(parsed)
        .send()
        .map_err(|_| "Не удалось скачать файл. Проверьте интернет.")?
        .error_for_status()
        .map_err(|_| "Файл релиза недоступен. Проверьте репозиторий и публикацию Release.")?;
    if response.content_length().is_some_and(|n| n > max) {
        return Err("Файл релиза слишком большой.".into());
    }
    let mut file = fs::File::create(dest).map_err(|_| "Не удалось создать временный файл.")?;
    let mut buf = [0u8; 32768];
    let mut total = 0u64;
    loop {
        let n = response.read(&mut buf).map_err(|_| "Загрузка прервана.")?;
        if n == 0 {
            break;
        }
        total += n as u64;
        if total > max {
            return Err("Превышен размер файла релиза.".into());
        }
        file.write_all(&buf[..n])
            .map_err(|_| "Не удалось записать EXE.")?
    }
    Ok(())
}
fn verify(exe: &Path, sums: &Path) -> Result<(), String> {
    let text = fs::read_to_string(sums).map_err(|_| "Не удалось прочитать SHA256SUMS.txt.")?;
    let expected = text
        .lines()
        .find_map(|l| {
            let mut p = l.split_whitespace();
            let hash = p.next()?;
            let file = p.next()?.trim_start_matches('*');
            (file == "CarCar.exe" && hash.len() == 64).then(|| hash.to_lowercase())
        })
        .ok_or("В SHA256SUMS.txt нет CarCar.exe.")?;
    let mut file = fs::File::open(exe).map_err(|_| "Не удалось проверить EXE.")?;
    let mut hash = Sha256::new();
    let mut buf = [0; 32768];
    loop {
        let n = file
            .read(&mut buf)
            .map_err(|_| "Не удалось прочитать EXE.")?;
        if n == 0 {
            break;
        }
        hash.update(&buf[..n]);
    }
    let actual = format!("{:x}", hash.finalize());
    if actual != expected {
        return Err("Контрольная сумма EXE не совпала. Запуск отменён.".into());
    }
    Ok(())
}
fn run() -> Result<(), String> {
    if std::env::args().any(|a| a == "--cleanup-only") {
        stale();
        return Ok(());
    }
    ensure_webview()?;
    stale();
    let here = std::env::current_exe()
        .map_err(|_| "Не удалось найти загрузчик.")?
        .parent()
        .ok_or("Не удалось найти папку загрузчика.")?
        .to_path_buf();
    let run_dir = root().join(uuid::Uuid::new_v4().to_string());
    fs::create_dir_all(&run_dir).map_err(|_| "Не удалось создать временную папку.")?;
    fs::write(run_dir.join("owner.pid"), std::process::id().to_string())
        .map_err(|_| "Не удалось создать маркер сеанса.")?;
    let result = (|| {
        let dest = run_dir.join("CarCar.exe");
        let local = here.join("CarCar.exe");
        if local.is_file() {
            fs::copy(&local, &dest)
                .map_err(|_| "Не удалось скопировать CarCar.exe во временную папку.")?;
            if here.join("SHA256SUMS.txt").is_file() {
                verify(&dest, &here.join("SHA256SUMS.txt"))?
            }
        } else {
            let repo=std::env::var("CARCAR_REPOSITORY").ok().or_else(||fs::read_to_string(here.join("repository.txt")).ok()).ok_or("Рядом нет CarCar.exe. Укажите CARCAR_REPOSITORY=владелец/репозиторий с опубликованным GitHub Release.")?;
            let repo = repo.trim();
            let parts: Vec<_> = repo.split('/').collect();
            if parts.len() != 2
                || parts.iter().any(|p| {
                    p.is_empty()
                        || !p
                            .bytes()
                            .all(|b| b.is_ascii_alphanumeric() || b"-_.".contains(&b))
                })
            {
                return Err("Репозиторий должен иметь формат owner/repository.".into());
            }
            let client = Client::builder()
                .user_agent("CarCar-Launcher/1.0")
                .connect_timeout(Duration::from_secs(15))
                .timeout(Duration::from_secs(180))
                .build()
                .map_err(|_| "Ошибка HTTPS-клиента.")?;
            let latest: serde_json::Value = client
                .get(format!(
                    "https://api.github.com/repos/{repo}/releases/latest"
                ))
                .header("Cache-Control", "no-cache")
                .send()
                .map_err(|_| "Не удалось получить сведения о релизе GitHub.")?
                .error_for_status()
                .map_err(|_| "GitHub не вернул релиз. Проверьте репозиторий или повторите позже.")?
                .json()
                .map_err(|_| "GitHub вернул неверный формат релиза.")?;
            let tag = latest["tag_name"]
                .as_str()
                .ok_or("GitHub не указал номер релиза.")?;
            if tag.is_empty()
                || !tag
                    .bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b"-_.".contains(&b))
            {
                return Err("Неподдерживаемый номер релиза GitHub.".into());
            }
            let base = format!("https://github.com/{repo}/releases/download/{tag}");
            println!("Скачивание CarCar из GitHub Releases…");
            download(
                &client,
                &format!("{base}/SHA256SUMS.txt"),
                &run_dir.join("SHA256SUMS.txt"),
                32768,
            )?;
            download(
                &client,
                &format!("{base}/CarCar.exe"),
                &dest,
                64 * 1024 * 1024,
            )?;
            verify(&dest, &run_dir.join("SHA256SUMS.txt"))?;
        }
        let mut app = Command::new(&dest);
        let config = here.join("carcar.local.env");
        if config.is_file() {
            app.env("CARCAR_CONFIG", config);
        }
        let mut child = app
            .spawn()
            .map_err(|_| "Не удалось запустить CarCar. Проверьте WebView2 Runtime.")?;
        fs::write(run_dir.join("app.pid"), child.id().to_string())
            .map_err(|_| "Не удалось создать маркер процесса.")?;
        let status = child
            .wait()
            .map_err(|_| "Не удалось дождаться завершения CarCar.")?;
        if !status.success() {
            return Err("CarCar завершился с ошибкой. Проверьте WebView2 Runtime.".into());
        }
        Ok(())
    })();
    if !cleanup(&run_dir) {
        eprintln!("Временная папка занята. Очистка будет повторена при следующем запуске.")
    }
    result
}
fn main() {
    if let Err(message) = run() {
        eprintln!("CarCar: {message}");
        std::process::exit(1)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn cleanup_is_scoped() {
        assert!(!safe(&std::env::temp_dir()));
        assert!(!safe(&root().join("other")));
        let p = root().join(uuid::Uuid::new_v4().to_string());
        fs::create_dir_all(&p).unwrap();
        fs::write(p.join("test"), "x").unwrap();
        assert!(safe(&p));
        assert!(cleanup(&p));
        assert!(!p.exists())
    }
    #[test]
    fn checksum_accepts_only_matching_binary() {
        let p = root().join(uuid::Uuid::new_v4().to_string());
        fs::create_dir_all(&p).unwrap();
        let exe = p.join("CarCar.exe");
        let sums = p.join("SHA256SUMS.txt");
        fs::write(&exe, b"abc").unwrap();
        fs::write(
            &sums,
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  CarCar.exe\n",
        )
        .unwrap();
        assert!(verify(&exe, &sums).is_ok());
        fs::write(&exe, b"changed").unwrap();
        assert!(verify(&exe, &sums).is_err());
        cleanup(&p);
    }
}
