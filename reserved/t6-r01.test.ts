import { expect, test } from "vitest";

import {
  InventoryManagement,
  type InitialProduct,
} from "../submission/src/index.ts";

test("T6-R01", () => {
  const inventory = createInventory();
  const order = inventory.createOrder([
    { productId: "P-001", quantity: 2 },
    { productId: "P-002", quantity: 7 },
    { productId: "P-003", quantity: 4 },
  ]);

  expect.soft(inventory.confirmOrder(order.orderId)).toEqual({
    orderId: "O-001",
    status: "partially-fulfilled",
    lines: [
      fulfillmentLine("P-001", 2, 0),
      fulfillmentLine("P-002", 7, 5),
      fulfillmentLine("P-003", 4, 4),
    ],
  });
  expect.soft(stockState(inventory)).toEqual({
    "P-001": 0,
    "P-002": 0,
    "P-003": 6,
  });
});

function createInventory(): InventoryManagement {
  const products: InitialProduct[] = [
    { productId: "P-001", name: "Tastiera", availableQuantity: 0 },
    { productId: "P-002", name: "Mouse", availableQuantity: 5 },
    { productId: "P-003", name: "Monitor", availableQuantity: 10 },
  ];
  return new InventoryManagement(products);
}

function fulfillmentLine(
  productId: string,
  requestedQuantity: number,
  fulfilledQuantity: number,
) {
  return {
    productId,
    requestedQuantity,
    fulfilledQuantity,
    remainingQuantity: requestedQuantity - fulfilledQuantity,
  };
}

function stockState(inventory: InventoryManagement) {
  return Object.fromEntries(
    inventory.listProducts().map(({ productId }) => [
      productId,
      inventory.getAvailableQuantity(productId),
    ]),
  );
}
