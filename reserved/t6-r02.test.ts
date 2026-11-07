import { expect, test } from "vitest";

import {
  InventoryManagement,
  type InitialProduct,
} from "../submission/src/index.ts";

test("T6-R02", () => {
  const products: InitialProduct[] = [
    { productId: "P-001", name: "Tastiera", availableQuantity: 0 },
    { productId: "P-002", name: "Mouse", availableQuantity: 5 },
    { productId: "P-003", name: "Monitor", availableQuantity: 10 },
  ];
  const inventory = new InventoryManagement(products);
  const firstCreated = inventory.createOrder([
    { productId: "P-002", quantity: 4 },
  ]);
  const secondCreated = inventory.createOrder([
    { productId: "P-002", quantity: 4 },
  ]);

  expect.soft(inventory.confirmOrder(secondCreated.orderId)).toEqual(
    expectedOrder("O-002", "fulfilled", 4, 0),
  );
  expect.soft(inventory.confirmOrder(firstCreated.orderId)).toEqual(
    expectedOrder("O-001", "partially-fulfilled", 1, 3),
  );
  expect(inventory.getAvailableQuantity("P-002")).toBe(0);
});

function expectedOrder(
  orderId: string,
  status: "partially-fulfilled" | "fulfilled",
  fulfilledQuantity: number,
  remainingQuantity: number,
) {
  return {
    orderId,
    status,
    lines: [
      {
        productId: "P-002",
        requestedQuantity: 4,
        fulfilledQuantity,
        remainingQuantity,
      },
    ],
  };
}
