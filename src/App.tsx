import { lazy, Suspense, useEffect, useRef, useState } from "react";
import {
  cancel,
  closeApp,
  copyText,
  generate,
  initialSettings,
  loadSettings,
  Message,
  Settings,
} from "./api";
import { Icon } from "./Icon";
const Answer = lazy(() => import("./Answer"));

function SettingsDialog({
  settings,
  onSave,
  onClose,
}: {
  settings: Settings;
  onSave: (s: Settings) => void;
  onClose: () => void;
}) {
  const [draft, setDraft] = useState({ ...settings }),
    [visible, setVisible] = useState(false),
    [error, setError] = useState("");
  const dialog = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    dialog.current?.showModal();
    return () => dialog.current?.close();
  }, []);
  function save(e: React.FormEvent) {
    e.preventDefault();
    try {
      const u = new URL(draft.baseUrl);
      if (
        u.protocol !== "https:" &&
        !(
          u.protocol === "http:" &&
          ["localhost", "127.0.0.1", "[::1]"].includes(u.hostname)
        )
      )
        throw 0;
      if (u.username || u.password || u.search || u.hash) throw 0;
    } catch {
      setError(
        "Введите HTTPS-адрес API без параметров. Для localhost разрешён HTTP.",
      );
      return;
    }
    if (!draft.apiKey.trim() || !draft.model.trim()) {
      setError("Укажите API Key и название модели.");
      return;
    }
    onSave({
      ...draft,
      baseUrl: draft.baseUrl.trim().replace(/\/+$/, ""),
      apiKey: draft.apiKey.trim(),
      model: draft.model.trim(),
    });
  }
  return (
    <dialog ref={dialog} className="settings" onCancel={onClose}>
      <form onSubmit={save}>
        <div className="dialog-head">
          <div>
            <span className="eyebrow">ПОДКЛЮЧЕНИЕ</span>
            <h2>Настройки API</h2>
          </div>
          <button
            type="button"
            className="icon-button"
            onClick={onClose}
            aria-label="Закрыть настройки"
          >
            <Icon name="close" />
          </button>
        </div>
        <label>
          API Base URL
          <input
            autoFocus
            type="url"
            value={draft.baseUrl}
            onChange={(e) => setDraft({ ...draft, baseUrl: e.target.value })}
            required
            spellCheck={false}
          />
        </label>
        <label>
          API Key
          <div className="key-input">
            <input
              type={visible ? "text" : "password"}
              value={draft.apiKey}
              onChange={(e) => setDraft({ ...draft, apiKey: e.target.value })}
              autoComplete="off"
              spellCheck={false}
              required
            />
            <button
              className="icon-button"
              type="button"
              aria-label={visible ? "Скрыть ключ" : "Показать ключ"}
              onClick={() => setVisible(!visible)}
            >
              <Icon name="eye" />
            </button>
          </div>
        </label>
        <label>
          Модель
          <input
            value={draft.model}
            onChange={(e) => setDraft({ ...draft, model: e.target.value })}
            required
            spellCheck={false}
          />
        </label>
        <div className="field-row">
          <label>
            Максимум токенов
            <input
              type="number"
              min="1"
              max="131072"
              value={draft.maxTokens}
              onChange={(e) =>
                setDraft({ ...draft, maxTokens: Number(e.target.value) })
              }
              required
            />
          </label>
          <label>
            Температура
            <input
              type="number"
              min="0"
              max="2"
              step="0.1"
              placeholder="По умолчанию API"
              value={draft.temperature ?? ""}
              onChange={(e) =>
                setDraft({
                  ...draft,
                  temperature:
                    e.target.value === "" ? null : Number(e.target.value),
                })
              }
            />
          </label>
        </div>
        <label className="checkbox">
          <input
            type="checkbox"
            checked={draft.stream}
            onChange={(e) => setDraft({ ...draft, stream: e.target.checked })}
          />
          Потоковый ответ
        </label>
        <p className="settings-note">
          <Icon name="shield" />
          Изменения действуют до закрытия. Диалог хранится только в памяти.
        </p>
        {error && (
          <p role="alert" className="error">
            {error}
          </p>
        )}
        <button className="primary save" type="submit">
          Применить
        </button>
      </form>
    </dialog>
  );
}

export default function App() {
  const [settings, setSettings] = useState(initialSettings),
    [loaded, setLoaded] = useState(false),
    [showSettings, setShowSettings] = useState(false);
  const [messages, setMessages] = useState<Message[]>([]),
    [input, setInput] = useState(""),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [copied, setCopied] = useState<number | null>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null),
    bottom = useRef<HTMLDivElement>(null),
    scroller = useRef<HTMLDivElement>(null);
  const mounted = useRef(true),
    inFlight = useRef(false),
    generation = useRef(0),
    follow = useRef(true);
  useEffect(() => {
    mounted.current = true;
    loadSettings()
      .then((s) => {
        if (mounted.current) {
          setSettings(s);
          setLoaded(true);
        }
      })
      .catch(() => {
        if (mounted.current) {
          setLoaded(true);
          setShowSettings(true);
        }
      });
    return () => {
      mounted.current = false;
    };
  }, []);
  useEffect(() => {
    if (follow.current) bottom.current?.scrollIntoView({ behavior: "instant" });
  }, [messages, busy]);
  useEffect(() => {
    const el = inputRef.current;
    if (el) {
      el.style.height = "auto";
      el.style.height = `${Math.min(el.scrollHeight, 128)}px`;
    }
  }, [input]);
  async function send() {
    if (inFlight.current || !input.trim() || !loaded) return;
    if (!settings.apiKey) {
      setShowSettings(true);
      return;
    }
    inFlight.current = true;
    const id = ++generation.current;
    const history: Message[] = [
      ...messages.filter((m) => m.content.trim()),
      { role: "user", content: input.trim() },
    ];
    setMessages([...history, { role: "assistant", content: "" }]);
    setInput("");
    setBusy(true);
    setError("");
    follow.current = true;
    try {
      await generate(history, settings, (text) => {
        if (mounted.current && generation.current === id)
          setMessages((old) => {
            const next = [...old];
            const last = next.length - 1;
            next[last] = { ...next[last], content: next[last].content + text };
            return next;
          });
      });
    } catch (e) {
      if (mounted.current && generation.current === id) setError(String(e));
    } finally {
      if (generation.current === id) {
        inFlight.current = false;
        if (mounted.current) {
          setBusy(false);
          inputRef.current?.focus();
        }
      }
    }
  }
  async function clear() {
    if (inFlight.current) {
      try {
        await cancel();
      } catch (e) {
        setError(String(e));
        return;
      }
    }
    generation.current++;
    inFlight.current = false;
    setBusy(false);
    setMessages([]);
    setError("");
    setInput("");
    inputRef.current?.focus();
  }
  async function stop() {
    try {
      await cancel();
    } catch {
      setError("Не удалось остановить запрос.");
    }
  }
  async function copy(text: string, index: number) {
    try {
      await copyText(text);
      setCopied(index);
      setTimeout(() => setCopied(null), 1600);
    } catch {
      setError("Не удалось скопировать ответ в буфер обмена.");
    }
  }
  return (
    <main className="app">
      <header className="titlebar" data-tauri-drag-region>
        <div className="brand" data-tauri-drag-region>
          <span className="brand-mark">
            <Icon name="spark" size={19} />
          </span>
          <span data-tauri-drag-region>CarCar</span>
          <span className="version">1.0</span>
        </div>
        <div className="window-actions">
          <button
            className="icon-button"
            title="Очистить диалог"
            aria-label="Очистить диалог"
            onClick={clear}
            disabled={!messages.length}
          >
            <Icon name="clear" />
          </button>
          <button
            className="icon-button"
            title="Настройки API"
            aria-label="Настройки API"
            onClick={() => setShowSettings(true)}
            disabled={busy}
          >
            <Icon name="settings" />
          </button>
          <span className="divider" />
          <button
            className="icon-button close"
            title="Закрыть CarCar"
            aria-label="Закрыть CarCar"
            onClick={() =>
              closeApp().catch(() => setError("Не удалось закрыть окно."))
            }
          >
            <Icon name="close" />
          </button>
        </div>
      </header>
      <div
        className="conversation"
        ref={scroller}
        onScroll={() => {
          const el = scroller.current;
          if (el)
            follow.current =
              el.scrollHeight - el.scrollTop - el.clientHeight < 90;
        }}
      >
        {!messages.length ? (
          <div className="welcome">
            <div className="welcome-mark">
              <Icon name="spark" size={30} />
            </div>
            <div className="eyebrow">ЕСТЬ ВОПРОС?</div>
            <h1>Давайте разберёмся.</h1>
            <p>
              От идеи до работающего кода.
              <br />И всё, что хочется понять.
            </p>
            <div className="suggestions">
              <button
                onClick={() => {
                  setInput("Помоги написать программу на Python.");
                  inputRef.current?.focus();
                }}
              >
                <Icon name="code" />
                Написать код
              </button>
              <button
                onClick={() => {
                  setInput("Объясни простыми словами, как работает ");
                  inputRef.current?.focus();
                }}
              >
                <Icon name="spark" />
                Объяснить тему
              </button>
            </div>
          </div>
        ) : (
          messages.map((m, i) => (
            <article key={i} className={`message ${m.role}`}>
              <div className="message-label">
                {m.role === "user" ? (
                  "ВЫ"
                ) : (
                  <>
                    <span className="mini-mark">
                      <Icon name="spark" size={12} />
                    </span>
                    CARCAR
                  </>
                )}
              </div>
              <div className="message-body">
                {m.role === "user" ? (
                  <p className="user-text">{m.content}</p>
                ) : (
                  <Suspense fallback={<p>{m.content}</p>}>
                    <Answer text={m.content} />
                  </Suspense>
                )}
              </div>
              {m.role === "assistant" && m.content && (
                <button
                  className="copy-answer"
                  onClick={() => copy(m.content, i)}
                >
                  <Icon name={copied === i ? "check" : "copy"} size={13} />
                  {copied === i ? "Скопировано" : "Копировать ответ"}
                </button>
              )}
              {m.role === "assistant" && busy && i === messages.length - 1 && (
                <div className="generating" role="status">
                  <span />
                  <span />
                  <span />
                  <span className="sr-only">Генерация ответа</span>
                </div>
              )}
            </article>
          ))
        )}
        {error && (
          <div className="error error-box" role="alert">
            {error}
          </div>
        )}
        <div ref={bottom} />
      </div>
      <footer className="composer-area">
        <div className="composer">
          <textarea
            ref={inputRef}
            autoFocus
            aria-label="Сообщение"
            placeholder="Спросите что-нибудь…"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => {
              if (
                e.key === "Enter" &&
                !e.shiftKey &&
                !e.nativeEvent.isComposing
              ) {
                e.preventDefault();
                send();
              }
            }}
            rows={1}
            maxLength={200000}
            disabled={busy}
          />
          <button
            className={`send-button ${busy ? "is-stop" : ""}`}
            aria-label={busy ? "Остановить генерацию" : "Отправить сообщение"}
            title={busy ? "Остановить" : "Отправить · Enter"}
            onClick={busy ? stop : send}
            disabled={!busy && (!input.trim() || !loaded)}
          >
            <Icon name={busy ? "stop" : "send"} size={19} />
          </button>
        </div>
        <div className="footer-meta">
          <span className="model-name">
            <span className={`status-dot ${busy ? "active" : ""}`} />
            {busy ? "Запрос к API" : settings.model}
          </span>
          <span>
            {busy ? (
              "Можно остановить"
            ) : (
              <>
                Enter <span className="muted">отправить</span>
                <span className="meta-separator">·</span>Shift + Enter{" "}
                <span className="muted">новая строка</span>
              </>
            )}
          </span>
        </div>
      </footer>
      {showSettings && (
        <SettingsDialog
          settings={settings}
          onClose={() => setShowSettings(false)}
          onSave={(s) => {
            setSettings(s);
            setShowSettings(false);
            setError("");
            inputRef.current?.focus();
          }}
        />
      )}
    </main>
  );
}
