import { Channel, invoke } from "@tauri-apps/api/core";
export type Settings = {
  apiKey: string;
  baseUrl: string;
  model: string;
  temperature: number | null;
  maxTokens: number;
  stream: boolean;
};
export type Message = { role: "user" | "assistant"; content: string };
export type Chunk = { text: string };
export const initialSettings: Settings = {
  apiKey: "",
  baseUrl: "https://darkapi.shop/v1",
  model: "gpt-5.6-luna",
  temperature: null,
  maxTokens: 4096,
  stream: true,
};
export async function loadSettings(): Promise<Settings> {
  return invoke("load_settings");
}
export async function generate(
  messages: Message[],
  settings: Settings,
  onChunk: (text: string) => void,
) {
  const onEvent = new Channel<Chunk>();
  onEvent.onmessage = (e) => onChunk(e.text);
  return invoke<void>("generate", { messages, settings, onEvent });
}
export const cancel = () => invoke<void>("cancel_generation");
export const copyText = (text: string) => invoke<void>("copy_text", { text });
export const closeApp = () => invoke<void>("close_app");
