import { test, expect } from "@playwright/test";
test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => {
    const w = window as any;
    w.calls = [];
    w.copied = "";
    w.response = "Текст ответа";
    w.failure = "";
    const callbacks: Record<number, Function> = {};
    let id = 0;
    let stopped = false;
    w.__TAURI_INTERNALS__ = {
      transformCallback: (fn: Function) => {
        callbacks[++id] = fn;
        return id;
      },
      unregisterCallback: (n: number) => delete callbacks[n],
      invoke: async (cmd: string, args: any) => {
        w.calls.push({ cmd, args });
        if (cmd === "load_settings")
          return {
            apiKey: "test-only",
            baseUrl: "https://api.example.test/v1",
            model: "test-model",
            temperature: null,
            maxTokens: 4096,
            stream: true,
          };
        if (cmd === "copy_text") {
          w.copied = args.text;
          return;
        }
        if (cmd === "cancel_generation") {
          stopped = true;
          return;
        }
        if (cmd === "generate") {
          stopped = false;
          if (w.failure) throw w.failure;
          const response = w.response;
          for (let n = 0; n < response.length; n += 18) {
            await new Promise((r) => setTimeout(r, 20));
            if (stopped) throw "Генерация остановлена.";
            args.onEvent.onmessage({ text: response.slice(n, n + 18) });
          }
          return;
        }
      },
    };
  });
  await page.goto("/");
});
test("sends, streams, formats Markdown, copies, clears and forgets on reload", async ({page}, testInfo) => {
  await page.evaluate(() => {
    (window as any).response =
      '## Готово\n\n```python\ndef greet(name):\n    return f"Привет, {name}"\n```\n\n| A | B |\n|---|---|\n| 1 | 2 |';
  });
  await page
    .getByRole("textbox", { name: "Сообщение", exact: true })
    .fill("Напиши функцию");
  await page
    .getByRole("button", { name: "Отправить сообщение", exact: true })
    .click();
  await expect(
    page.getByRole("button", { name: "Остановить генерацию" }),
  ).toBeVisible();
  await expect(page.getByRole("heading", { name: "Готово" })).toBeVisible();
  await expect(page.locator(".cm-content")).toContainText("def greet(name):");
  await expect(page.locator("table")).toBeVisible();
  await expect(page.locator(".cm-content span").first()).toBeVisible();
  await page
    .getByRole("button", { name: "Копировать код", exact: true })
    .click();
  await expect
    .poll(() => page.evaluate(() => (window as any).copied))
    .toContain("def greet(name)");
  await page
    .getByRole("button", { name: "Копировать ответ", exact: true })
    .click();
  await expect
    .poll(() => page.evaluate(() => (window as any).copied))
    .toContain("## Готово");
  await page.screenshot({ path: testInfo.outputPath("chat.png") });
  await page.getByRole("button", { name: "Очистить диалог" }).click();
  await expect(
    page.getByRole("heading", { name: "Давайте разберёмся." }),
  ).toBeVisible();
  await page.reload();
  await expect(page.locator("article")).toHaveCount(0);
  expect(await page.evaluate(() => Object.keys(localStorage))).toEqual([]);
  expect(await page.evaluate(() => Object.keys(sessionStorage))).toEqual([]);
});
test("changes credentials and model for the next request", async ({ page }) => {
  await page
    .getByRole("button", { name: "Настройки API", exact: true })
    .click();
  await page
    .getByLabel("API Key", { exact: true })
    .fill("replacement-test-only");
  await page.getByLabel("Модель", { exact: true }).fill("another-model");
  await page.getByLabel("Температура", { exact: true }).fill("0.4");
  await page.getByRole("button", { name: "Применить" }).click();
  await page
    .getByRole("textbox", { name: "Сообщение", exact: true })
    .fill("Тест");
  await page.keyboard.press("Enter");
  await expect(
    page.getByRole("button", { name: "Копировать ответ" }),
  ).toBeVisible();
  const s = await page.evaluate(
    () =>
      (window as any).calls.find((c: any) => c.cmd === "generate").args
        .settings,
  );
  expect(s.apiKey).toBe("replacement-test-only");
  expect(s.model).toBe("another-model");
  expect(s.temperature).toBe(0.4);
});
test("handles provider errors and prevents external Markdown requests", async ({
  page,
}) => {
  await page.evaluate(() => {
    (window as any).failure =
      "API не принял ключ. Проверьте API Key и права доступа.";
  });
  await page
    .getByRole("textbox", { name: "Сообщение", exact: true })
    .fill("test");
  await page.keyboard.press("Enter");
  await expect(page.getByRole("alert")).toContainText("не принял ключ");
  await expect(
    page.getByRole("button", { name: "Отправить сообщение", exact: true }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Очистить диалог" }).click();
  await page.evaluate(() => {
    (window as any).failure = "";
    (window as any).response =
      "![x](https://tracking.example.test/a) [ссылка](https://example.test) <script>alert(1)</script>";
  });
  await page
    .getByRole("textbox", { name: "Сообщение", exact: true })
    .fill("test");
  await page.keyboard.press("Enter");
  await expect(
    page.getByRole("button", { name: "Копировать ответ" }),
  ).toBeVisible();
  await expect(page.locator("img")).toHaveCount(0);
  await expect(page.locator("a")).toHaveCount(0);
  await expect(page.locator(".message-body script")).toHaveCount(0);
});
test("cancels generation and supports compact window", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 470 });
  await page.evaluate(() => {
    (window as any).response = "Ответ ".repeat(300);
  });
  await page
    .getByRole("textbox", { name: "Сообщение", exact: true })
    .fill("Долго");
  await page.keyboard.press("Enter");
  await page.getByRole("button", { name: "Остановить генерацию" }).click();
  await expect(page.getByRole("alert")).toContainText("остановлена");
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBeTruthy();
  await page.getByRole("button", { name: "Настройки API" }).click();
  await expect(page.getByRole("dialog")).toBeVisible();
});
test("highlights all nine required languages", async ({ page }) => {
  const snippets = {
    python: "def add(a, b):\n    return a + b",
    javascript: "const add = (a, b) => a + b;",
    typescript: "const value: number = 42;",
    rust: "fn main() { let value = 42; }",
    cpp: "int main() { return 0; }",
    java: "class Main { int value = 42; }",
    html: '<div class="test">Hello</div>',
    css: ".test { color: red; }",
    sql: "SELECT id FROM users WHERE id = 1;",
  };
  await page.evaluate((s) => {
    (window as any).response = Object.entries(s)
      .map(([l, c]) => "```" + l + "\n" + c + "\n```")
      .join("\n\n");
  }, snippets);
  await page
    .getByRole("textbox", { name: "Сообщение", exact: true })
    .fill("Все языки");
  await page.keyboard.press("Enter");
  await expect(
    page.getByRole("button", { name: "Копировать ответ" }),
  ).toBeVisible();
  await expect(page.locator(".cm-content")).toHaveCount(9);
  for (const language of Object.keys(snippets)) {
    const block = page
      .locator(".code-block")
      .filter({
        has: page.locator(".code-toolbar > span", {
          hasText: new RegExp("^" + language + "$"),
        }),
      });
    await expect(block.locator(".cm-content span").first()).toBeAttached();
  }
});
