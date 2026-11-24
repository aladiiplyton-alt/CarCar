import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import CodeBlock from "./CodeBlock";

export default function Answer({ text }: { text: string }) {
  return (
    <ReactMarkdown
      remarkPlugins={[remarkGfm]}
      skipHtml
      components={{
        pre: ({ children }) => <>{children}</>,
        code: ({ className, children, ...props }) => {
          const lang = /language-([^ ]+)/.exec(className || "")?.[1];
          const code = String(children).replace(/\n$/, "");
          return lang || String(children).endsWith("\n") ? (
            <CodeBlock code={code} language={lang || ""} />
          ) : (
            <code {...props}>{children}</code>
          );
        },
        // Markdown cannot initiate requests to third-party servers.
        img: ({ alt }) => (
          <span className="image-alt">
            [Изображение: {alt || "без описания"}]
          </span>
        ),
        a: ({ children, href }) => (
          <span className="text-link" title={href}>
            {children}
            {href && <> ({href})</>}
          </span>
        ),
      }}
    >
      {text}
    </ReactMarkdown>
  );
}
