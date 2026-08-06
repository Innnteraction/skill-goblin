import { saveOrder } from "./repository";

export interface Notifier {
  notify(): void;
}

export function createOrder(payload: unknown) {
  const saved = saveOrder(payload);
  return saved;
}

export async function loadOptional() {
  return import("./worker");
}
