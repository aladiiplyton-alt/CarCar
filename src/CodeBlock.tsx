import { useEffect, useRef, useState } from "react";
import { EditorState } from "@codemirror/state";
import { EditorView } from "@codemirror/view";
import {
  syntaxHighlighting,
  HighlightStyle,
  LanguageSupport,
} from "@codemirror/language";
import { tags } from "@lezer/highlight";
import { copyText } from "./api";
import { Icon } from "./Icon";
const loaders: Record<string, () => Promise<LanguageSupport>> = {
  python: () => import("@codemirror/lang-python").then((m) => m.python()),
  javascript: () =>
    import("@codemirror/lang-javascript").then((m) => m.javascript()),
  typescript: () =>
    import("@codemirror/lang-javascript").then((m) =>
      m.javascript({ typescript: true }),
    ),
  jsx: () =>
    import("@codemirror/lang-javascript").then((m) =>
      m.javascript({ jsx: true }),
    ),
  tsx: () =>
    import("@codemirror/lang-javascript").then((m) =>
      m.javascript({ jsx: true, typescript: true }),
    ),
  rust: () => import("@codemirror/lang-rust").then((m) => m.rust()),
  cpp: () => import("@codemirror/lang-cpp").then((m) => m.cpp()),
  java: () => import("@codemirror/lang-java").then((m) => m.java()),
  html: () => import("@codemirror/lang-html").then((m) => m.html()),
  css: () => import("@codemirror/lang-css").then((m) => m.css()),
  sql: () => import("@codemirror/lang-sql").then((m) => m.sql()),
};
const aliases: Record<string, string> = {
  py: "python",
  js: "javascript",
  ts: "typescript",
  "c++": "cpp",
  c: "cpp",
  rs: "rust",
  htm: "html",
};
export function normalizeLanguage(name: string) {
  const n = name.toLowerCase();
  return aliases[n] || n;
}
const highlight = HighlightStyle.define([
  { tag: tags.keyword, color: "#c7a6ef" },
  { tag: tags.string, color: "#b7d7a0" },
  { tag: [tags.number, tags.bool], color: "#e4b77e" },
  { tag: tags.comment, color: "#818b96", fontStyle: "italic" },
  { tag: [tags.function(tags.variableName), tags.tagName], color: "#9dcaee" },
  { tag: [tags.typeName, tags.className], color: "#e5cc97" },
  { tag: tags.operator, color: "#b1bac5" },
]);
export default function CodeBlock({
  code,
  language,
}: {
  code: string;
  language: string;
}) {
  const host = useRef<HTMLDivElement>(null),
    view = useRef<EditorView | null>(null);
  const latest = useRef(code);
  latest.current = code;
  const [copied, setCopied] = useState(false),
    [error, setError] = useState("");
  const lang = normalizeLanguage(language);
  useEffect(() => {
    let active = true;
    let editor: EditorView | undefined;
    (async () => {
      const syntax = loaders[lang] ? await loaders[lang]() : [];
      if (!active || !host.current) return;
      editor = new EditorView({
        parent: host.current,
        state: EditorState.create({
          doc: latest.current,
          extensions: [
            EditorState.readOnly.of(true),
            EditorView.editable.of(false),
            EditorView.contentAttributes.of({
              "aria-label": `Код ${language || "text"}`,
            }),
            EditorView.theme(
              {
                "&": {
                  backgroundColor: "transparent",
                  color: "#d9e0e7",
                  fontSize: "12px",
                },
                ".cm-content": {
                  fontFamily: "Cascadia Code, Consolas, monospace",
                  padding: "16px",
                },
                ".cm-line": { padding: "0" },
                ".cm-scroller": { overflow: "auto" },
                "&.cm-focused": { outline: "none" },
              },
              { dark: true },
            ),
            syntaxHighlighting(highlight),
            syntax,
          ],
        }),
      });
      view.current = editor;
    })().catch(() => setError("Не удалось включить подсветку."));
    return () => {
      active = false;
      editor?.destroy();
      view.current = null;
    };
    // Recreate only on language changes; incremental updates keep selection stable.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [lang]);
  useEffect(() => {
    const v = view.current;
    if (v && v.state.doc.toString() !== code)
      v.dispatch({
        changes: { from: 0, to: v.state.doc.length, insert: code },
      });
  }, [code]);
  async function copy() {
    try {
      await copyText(code);
      setCopied(true);
      setTimeout(() => setCopied(false), 1800);
    } catch {
      setError("Не удалось скопировать код.");
    }
  }
  return (
    <section className="code-block">
      <div className="code-toolbar">
        <span>{lang || "text"}</span>
        <button onClick={copy} aria-label="Копировать код">
          <Icon name={copied ? "check" : "copy"} />
          {copied ? "Скопировано" : "Копировать"}
        </button>
      </div>
      <div ref={host} />
      {error && <small role="alert">{error}</small>}
    </section>
  );
}
