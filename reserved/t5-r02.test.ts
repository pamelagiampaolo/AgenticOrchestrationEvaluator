import { expect, test } from "vitest";

import {
  createInventoryManagementWithRepositories,
  type InitialProduct,
  type Order,
  type Product,
} from "../submission/src/index.ts";

const standardProducts: InitialProduct[] = [
  { productId: "P-001", name: "Tastiera", availableQuantity: 0 },
  { productId: "P-002", name: "Mouse", availableQuantity: 5 },
  { productId: "P-003", name: "Monitor", availableQuantity: 10 },
];

test("T5-R02", () => {
  const products = new ProductDouble(standardProducts);
  const inventory = new InventoryDouble(standardProducts);
  const orders = new OrderDouble();
  const system = createInventoryManagementWithRepositories(
    products,
    inventory,
    orders,
  );

  const created = system.createOrder([
    { productId: "P-002", quantity: 2 },
  ]);
  const confirmed = system.confirmOrder(created.orderId);
  const expectedOrder: Order = {
    orderId: "O-001",
    status: "confirmed",
    lines: [{ productId: "P-002", quantity: 2 }],
  };

  expect.soft(confirmed).toEqual(expectedOrder);
  expect.soft(inventory.quantity("P-002")).toBe(3);
  expect.soft(orders.order("O-001")).toEqual(expectedOrder);
  expect.soft({
    productRepositoryUsed: products.used,
    inventoryRepositoryUsed: inventory.used,
    orderRepositoryUsed: orders.used,
  }).toEqual({
    productRepositoryUsed: true,
    inventoryRepositoryUsed: true,
    orderRepositoryUsed: true,
  });
});

class ProductDouble {
  public used = false;

  public constructor(private readonly values: readonly Product[]) {}

  public findById(productId: string): Product | undefined {
    this.used = true;
    const product = this.values.find((value) => value.productId === productId);
    return product === undefined ? undefined : { ...product };
  }

  public list(): Product[] {
    this.used = true;
    return this.values.map((value) => ({ ...value }));
  }
}

class InventoryDouble {
  public used = false;
  private readonly quantities: Map<string, number>;

  public constructor(products: readonly InitialProduct[]) {
    this.quantities = new Map(
      products.map((product) => [
        product.productId,
        product.availableQuantity,
      ]),
    );
  }

  public getAvailableQuantity(productId: string): number | undefined {
    this.used = true;
    return this.quantities.get(productId);
  }

  public setAvailableQuantity(productId: string, quantity: number): void {
    this.used = true;
    this.quantities.set(productId, quantity);
  }

  public quantity(productId: string): number | undefined {
    return this.quantities.get(productId);
  }
}

class OrderDouble {
  public used = false;
  private readonly orders = new Map<string, Order>();

  public findById(orderId: string): Order | undefined {
    this.used = true;
    return copyOrder(this.orders.get(orderId));
  }

  public list(): Order[] {
    this.used = true;
    return [...this.orders.values()].map((order) => copyOrder(order)!);
  }

  public save(order: Order): void {
    this.used = true;
    this.orders.set(order.orderId, copyOrder(order)!);
  }

  public order(orderId: string): Order | undefined {
    return copyOrder(this.orders.get(orderId));
  }
}

function copyOrder(order: Order | undefined): Order | undefined {
  return order === undefined
    ? undefined
    : {
        ...order,
        lines: order.lines.map((line) => ({ ...line })),
      };
}
