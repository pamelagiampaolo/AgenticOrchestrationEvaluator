import { expect, test } from "vitest";

import {
  InventoryManagement,
  type InitialProduct,
} from "../submission/src/index.ts";

test("T6-R03", () => {
  const products: InitialProduct[] = [
    { productId: "P-001", name: "Tastiera", availableQuantity: 0 },
    { productId: "P-002", name: "Mouse", availableQuantity: 5 },
    { productId: "P-003", name: "Monitor", availableQuantity: 10 },
  ];
  const inventory = new InventoryManagement(products);
  const order = inventory.createOrder([
    { productId: "P-001", quantity: 4 },
  ]);
  inventory.confirmOrder(order.orderId);
  inventory.receiveStock("P-001", 2);
  inventory.fulfillOrder(order.orderId);
  const stockBeforeInvalidLoad = inventory.getAvailableQuantity("P-001");
  const orderBeforeInvalidLoad = inventory.getOrder(order.orderId);

  expect(() => inventory.receiveStock("P-001", -1)).toThrowError(
    expect.objectContaining({ code: "INVALID_QUANTITY" }),
  );
  expect.soft(inventory.getAvailableQuantity("P-001")).toBe(
    stockBeforeInvalidLoad,
  );
  expect.soft(inventory.getOrder(order.orderId)).toEqual(orderBeforeInvalidLoad);
  expect(orderBeforeInvalidLoad).toEqual({
    orderId: "O-001",
    status: "partially-fulfilled",
    lines: [
      {
        productId: "P-001",
        requestedQuantity: 4,
        fulfilledQuantity: 2,
        remainingQuantity: 2,
      },
    ],
  });
});
