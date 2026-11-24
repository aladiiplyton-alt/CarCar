use futures_util::StreamExt;
use reqwest::{Client, Url};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::time::Duration;
use tokio_util::sync::CancellationToken;
use zeroize::{Zeroize, ZeroizeOnDrop, Zeroizing};

#[derive(Clone, Deserialize, Serialize, Zeroize, ZeroizeOnDrop)]
#[serde(rename_all = "camelCase")]
pub struct Settings {
    pub api_key: String,
    pub base_url: String,
    pub model: String,
    pub temperature: Option<f64>,
    pub max_tokens: u32,
    pub stream: bool,
}
impl Default for Settings {
    fn default() -> Self {
        Self {
            api_key: String::new(),
            base_url: "https://darkapi.shop/v1".into(),
            model: "gpt-5.6-luna".into(),
            temperature: None,
            max_tokens: 4096,
            stream: true,
        }
    }
}
#[derive(Deserialize, Serialize)]
pub struct Message {
    pub role: String,
    pub content: String,
}
impl Drop for Message {
    fn drop(&mut self) {
        self.content.zeroize();
    }
}
#[derive(Serialize, Clone)]
pub struct Chunk {
    pub text: String,
}

pub fn endpoint(settings: &Settings) -> Result<Url, String> {
    let raw = settings.base_url.trim().trim_end_matches('/');
    let mut url = Url::parse(raw).map_err(|_| "Неверный адрес API.")?;
    if url.scheme() != "https"
        && !(url.scheme() == "http"
            && matches!(
                url.host_str(),
                Some("localhost" | "127.0.0.1" | "[::1]" | "::1")
            ))
    {
        return Err("Используйте HTTPS. HTTP разрешён только для localhost.".into());
    }
    if !url.username().is_empty()
        || url.password().is_some()
        || url.query().is_some()
        || url.fragment().is_some()
    {
        return Err("Адрес API не должен содержать пароль, параметры или якорь.".into());
    }
    let path = format!("{}/chat/completions", url.path().trim_end_matches('/'));
    url.set_path(&path);
    if settings.api_key.trim().is_empty() {
        return Err("Укажите API Key в настройках.".into());
    }
    if settings.model.trim().is_empty() {
        return Err("Укажите название модели.".into());
    }
    if !(1..=131072).contains(&settings.max_tokens) {
        return Err("Максимум токенов: от 1 до 131072.".into());
    }
    if settings
        .temperature
        .is_some_and(|v| !v.is_finite() || !(0.0..=2.0).contains(&v))
    {
        return Err("Температура: от 0 до 2.".into());
    }
    Ok(url)
}
pub fn http_error(code: u16) -> String {
    match code {
 401|403=>"API не принял ключ. Проверьте API Key и права доступа.",
 404=>"API или модель не найдены. Проверьте Base URL и название модели.",
 400|422=>"API отклонил параметры. Проверьте модель, лимит токенов и отключите температуру, если модель её не поддерживает.",
 408|504=>"Превышено время ожидания API. Попробуйте ещё раз.",
 429=>"Достигнут лимит запросов или баланса провайдера. Повторите позже.",
 500..=599=>"Сервис API временно недоступен. Повторите позже.",
 _=>"API вернул ошибку. Проверьте настройки подключения."
 }.into()
}
fn network_error(error: reqwest::Error) -> String {
    if error.is_timeout() {
        "Превышено время ожидания. Проверьте интернет и повторите запрос."
    } else if error.is_connect() {
        "Не удалось подключиться к API. Проверьте интернет и Base URL."
    } else {
        "Соединение с API прервано. Повторите запрос."
    }
    .into()
}

// Byte framing preserves UTF-8 split across TCP packets and accepts LF and CRLF SSE.
#[derive(Default)]
pub struct Sse {
    pending: Vec<u8>,
    data: Vec<String>,
}
impl Drop for Sse {
    fn drop(&mut self) {
        self.pending.zeroize();
        for d in &mut self.data {
            d.zeroize();
        }
    }
}
impl Sse {
    pub fn push(&mut self, bytes: &[u8], eof: bool) -> Result<Vec<String>, String> {
        self.pending.extend_from_slice(bytes);
        if self.pending.len() > 2 * 1024 * 1024 {
            return Err("Слишком большой фрагмент ответа API.".into());
        }
        let mut events = Vec::new();
        while let Some(n) = self.pending.iter().position(|b| *b == b'\n') {
            let line: Vec<u8> = self.pending.drain(..=n).collect();
            self.line(&line, &mut events)?;
        }
        if eof {
            if !self.pending.is_empty() {
                let line = std::mem::take(&mut self.pending);
                self.line(&line, &mut events)?;
            }
            self.flush(&mut events)
        }
        Ok(events)
    }
    fn line(&mut self, line: &[u8], events: &mut Vec<String>) -> Result<(), String> {
        let s = std::str::from_utf8(line)
            .map_err(|_| "API вернул некорректный UTF-8.")?
            .trim_end_matches(['\r', '\n']);
        if s.is_empty() {
            self.flush(events)
        } else if let Some(v) = s.strip_prefix("data:") {
            self.data.push(v.strip_prefix(' ').unwrap_or(v).to_string())
        }
        Ok(())
    }
    fn flush(&mut self, events: &mut Vec<String>) {
        if !self.data.is_empty() {
            events.push(self.data.join("\n"));
            self.data.clear()
        }
    }
}
fn delta(data: &str) -> Result<Option<String>, String> {
    let v: Value =
        serde_json::from_str(data).map_err(|_| "API вернул некорректный формат ответа.")?;
    if v.get("error").is_some() {
        return Err("API прервал генерацию. Проверьте модель, ключ и баланс провайдера.".into());
    }
    if v.get("choices").and_then(Value::as_array).is_none() {
        return Err("В ответе API отсутствует поле choices.".into());
    }
    Ok(v.pointer("/choices/0/delta/content")
        .and_then(Value::as_str)
        .map(str::to_owned))
}
pub async fn request(
    settings: Settings,
    messages: Vec<Message>,
    cancel: CancellationToken,
    mut emit: impl FnMut(String) -> Result<(), String>,
) -> Result<(), String> {
    let url = endpoint(&settings)?;
    if messages.is_empty()
        || messages.len() > 500
        || messages
            .iter()
            .any(|m| !matches!(m.role.as_str(), "user" | "assistant") || m.content.len() > 800000)
    {
        return Err(
            "Диалог слишком большой или имеет неверный формат. Очистите его и повторите запрос."
                .into(),
        );
    }
    let client = Client::builder()
        .user_agent("CarCar/1.0")
        .connect_timeout(Duration::from_secs(15))
        .timeout(Duration::from_secs(300))
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .map_err(|_| "Не удалось создать подключение к API.")?;
    let mut body = json!({"model":settings.model,"messages":messages,"max_tokens":settings.max_tokens,"stream":settings.stream});
    if let Some(t) = settings.temperature {
        body["temperature"] = json!(t)
    }
    // Do not hold a JSON copy of the conversation throughout the request.
    let payload =
        Zeroizing::new(serde_json::to_vec(&body).map_err(|_| "Не удалось создать запрос.")?);
    drop(body);
    drop(messages);
    let response = client
        .post(url)
        .bearer_auth(&settings.api_key)
        .header("Content-Type", "application/json")
        .header(
            "Accept",
            if settings.stream {
                "text/event-stream"
            } else {
                "application/json"
            },
        )
        .body(payload.to_vec())
        .send()
        .await
        .map_err(network_error)?;
    if !response.status().is_success() {
        return Err(http_error(response.status().as_u16()));
    }
    let is_sse = response
        .headers()
        .get("content-type")
        .and_then(|h| h.to_str().ok())
        .is_some_and(|h| h.contains("text/event-stream"));
    let mut stream = response.bytes_stream();
    let mut sse = Sse::default();
    let mut json_bytes = Zeroizing::new(Vec::new());
    let mut received = 0usize;
    let mut total = 0usize;
    let mut finished = false;
    loop {
        let next = tokio::select! {biased; _=cancel.cancelled()=>return Err("Генерация остановлена.".into()),v=tokio::time::timeout(Duration::from_secs(60),stream.next())=>v.map_err(|_|"API не отвечает более 60 секунд. Попробуйте ещё раз.")?};
        let eof = next.is_none();
        let bytes = match next {
            Some(b) => b.map_err(network_error)?.to_vec(),
            None => Vec::new(),
        };
        total += bytes.len();
        if total > 16 * 1024 * 1024 {
            return Err("Превышен размер ответа (16 МБ). Уменьшите лимит токенов.".into());
        }
        if is_sse {
            for event in sse.push(&bytes, eof)? {
                if event.trim() == "[DONE]" {
                    finished = true;
                    break;
                }
                if let Some(text) = delta(&event)? {
                    received += text.len();
                    emit(text)?
                }
            }
        } else {
            json_bytes.extend_from_slice(&bytes)
        }
        if finished || eof {
            break;
        }
    }
    if !is_sse {
        let value: Value = serde_json::from_slice(&json_bytes)
            .map_err(|_| "API вернул некорректный JSON вместо ответа.")?;
        let text = value
            .pointer("/choices/0/message/content")
            .and_then(Value::as_str)
            .ok_or("API вернул неподдерживаемый формат ответа.")?;
        received = text.len();
        if !text.trim().is_empty() {
            emit(text.to_owned())?
        }
    }
    if received == 0 {
        return Err(
            "API вернул пустой ответ. Попробуйте другую модель или увеличьте лимит токенов.".into(),
        );
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    fn settings() -> Settings {
        let mut s = Settings::default();
        s.api_key = "test-only".into();
        s
    }
    #[test]
    fn validates_endpoint() {
        let mut s = settings();
        assert_eq!(
            endpoint(&s).unwrap().as_str(),
            "https://darkapi.shop/v1/chat/completions"
        );
        s.base_url = "http://evil.test/v1".into();
        assert!(endpoint(&s).is_err());
        s.base_url = "http://127.0.0.1:8765/v1".into();
        assert!(endpoint(&s).is_ok());
        s.base_url = "https://api.test/v1?key=secret".into();
        assert!(endpoint(&s).is_err());
    }
    #[test]
    fn sse_split_utf8_and_crlf() {
        let mut parser = Sse::default();
        let bytes =
            "data: {\"choices\":[{\"delta\":{\"content\":\"Привет\"}}]}\r\n\r\ndata: [DONE]\n\n"
                .as_bytes();
        let mut events = vec![];
        for b in bytes {
            events.extend(parser.push(&[*b], false).unwrap())
        }
        assert_eq!(delta(&events[0]).unwrap().unwrap(), "Привет");
        assert_eq!(events[1], "[DONE]");
    }
    #[test]
    fn sse_multiline_eof_comments() {
        let mut p = Sse::default();
        let events = p.push(b": ping\ndata: one\ndata: two", true).unwrap();
        assert_eq!(events, vec!["one\ntwo"]);
    }
    #[test]
    fn errors_are_safe() {
        assert!(http_error(401).contains("ключ"));
        assert!(http_error(429).contains("лимит"));
        assert!(delta("garbage").is_err());
        assert!(delta("{\"error\":{\"message\":\"private content\"}}")
            .unwrap_err()
            .find("private")
            .is_none());
    }
    #[tokio::test]
    #[ignore = "Uses configured provider; run explicitly only"]
    async fn real_provider_smoke() {
        let mut s = crate::load_settings();
        assert!(!s.api_key.is_empty(), "Set CARCAR_CONFIG");
        s.max_tokens = 256;
        s.stream = true;
        eprintln!("Testing model: {}", s.model);
        let mut out = String::new();
        request(s,vec![Message{role:"user".into(),content:"Напиши короткую функцию Python add(a, b), возвращающую сумму. Используй Markdown-блок кода python.".into()}],CancellationToken::new(),|t|{out.push_str(&t);Ok(())}).await.unwrap();
        assert!(out.contains("def "));
        assert!(out.contains("```"));
    }
    #[tokio::test]
    async fn json_and_stream_fallback() {
        use std::{
            io::{Read, Write},
            net::TcpListener,
        };
        for (ct, body) in [
            (
                "application/json",
                "{\"choices\":[{\"message\":{\"content\":\"hello\"}}]}",
            ),
            (
                "text/event-stream",
                "data: {\"choices\":[{\"delta\":{\"content\":\"hello\"}}]}\n\ndata: [DONE]\n\n",
            ),
        ] {
            let server = TcpListener::bind("127.0.0.1:0").unwrap();
            let port = server.local_addr().unwrap().port();
            let content = body.to_string();
            let handle = std::thread::spawn(move || {
                let (mut socket, _) = server.accept().unwrap();
                let mut buf = [0; 16384];
                let _ = socket.read(&mut buf);
                write!(socket,"HTTP/1.1 200 OK\r\nContent-Type: {ct}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",content.len(),content).unwrap()
            });
            let mut s = settings();
            s.base_url = format!("http://127.0.0.1:{port}/v1");
            let mut out = String::new();
            request(
                s,
                vec![Message {
                    role: "user".into(),
                    content: "test".into(),
                }],
                CancellationToken::new(),
                |t| {
                    out.push_str(&t);
                    Ok(())
                },
            )
            .await
            .unwrap();
            assert_eq!(out, "hello");
            handle.join().unwrap();
        }
    }
    #[tokio::test]
    async fn handles_http_empty_malformed_and_cancel() {
        use std::{
            io::{Read, Write},
            net::TcpListener,
        };
        for (status, body, expected) in [
            (401, "{}", "ключ"),
            (404, "{}", "модель"),
            (429, "{}", "лимит"),
            (503, "{}", "недоступен"),
            (
                200,
                "{\"choices\":[{\"message\":{\"content\":\"\"}}]}",
                "пустой",
            ),
            (200, "not-json", "JSON"),
        ] {
            let server = TcpListener::bind("127.0.0.1:0").unwrap();
            let port = server.local_addr().unwrap().port();
            let handle = std::thread::spawn(move || {
                let (mut socket, _) = server.accept().unwrap();
                let mut buf = [0; 16384];
                let _ = socket.read(&mut buf);
                write!(socket,"HTTP/1.1 {status} Test\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",body.len()).unwrap()
            });
            let mut s = settings();
            s.base_url = format!("http://127.0.0.1:{port}/v1");
            let result = request(
                s,
                vec![Message {
                    role: "user".into(),
                    content: "test".into(),
                }],
                CancellationToken::new(),
                |_| Ok(()),
            )
            .await;
            assert!(result.unwrap_err().contains(expected));
            handle.join().unwrap();
        }
        let token = CancellationToken::new();
        token.cancel();
        let s = settings();
        let result = tokio::select! {biased;_=token.cancelled()=>Err::<(),_>("Генерация остановлена.".to_string()),r=request(s,vec![Message{role:"user".into(),content:"test".into()}],token.clone(),|_|Ok(()))=>r};
        assert!(result.unwrap_err().contains("остановлена"));
    }
}
