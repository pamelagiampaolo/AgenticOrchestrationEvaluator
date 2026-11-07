import { expect, test } from "vitest";

import {
  InventoryManagement,
  type InitialProduct,
} from "../submission/src/index.ts";

test("T2-R03", () => {
  const products: InitialProduct[] = [
    { productId: "P-001", name: "Tastiera", availableQuantity: 0 },
    { productId: "P-002", name: "Mouse", availableQuantity: 5 },
    { productId: "P-003", name: "Monitor", availableQuantity: 10 },
  ];
  const inventory = new InventoryManagement(products);
  inventory.createOrder([{ productId: "P-003", quantity: 2 }]);
  const stateBeforeLoad = readObservableState(inventory);

  expect(inventory.receiveStock("P-002", 2)).toBe(7);
  expect(readObservableState(inventory)).toEqual({
    ...stateBeforeLoad,
    availableQuantities: stateBeforeLoad.availableQuantities.map((stock) =>
      stock.productId === "P-002"
        ? { productId: "P-002", availableQuantity: 7 }
        : stock,
    ),
  });
});

function readObservableState(inventory: InventoryManagement) {
  const products = inventory.listProducts();

  return {
    products,
    availableQuantities: products.map(({ productId }) => ({
      productId,
      availableQuantity: inventory.getAvailableQuantity(productId),
    })),
    orders: inventory.listOrders(),
  };
}
