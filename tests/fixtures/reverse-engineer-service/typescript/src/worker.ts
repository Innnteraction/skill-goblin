const queue = { on(_name: string, _handler: unknown) {} };

export function consumeOrder(message: unknown) {
  return message;
}

queue.on("order.created", consumeOrder);
