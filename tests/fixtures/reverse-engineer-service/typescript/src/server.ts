import { createOrder } from "@app/service";

const app = { post(_path: string, _handler: unknown) {} };

export async function postOrder(payload: unknown) {
  return createOrder(payload);
}

app.post("/orders", postOrder);
