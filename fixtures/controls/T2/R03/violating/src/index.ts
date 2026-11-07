export type Product = {
  productId: string;
  name: string;
};

export type InitialProduct = Product & {
  availableQuantity: number;
};

export type OrderLine = {
  productId: string;
  quantity: number;
};

export type Order = {
  orderId: string;
  status: "draft";
  lines: OrderLine[];
};

export class InventoryManagement {
  private readonly products: Product[];
  private readonly availableQuantities: Map<string, number>;
  private readonly orders: Order[] = [];

  public constructor(initialProducts: InitialProduct[]) {
    this.products = initialProducts.map(({ productId, name }) => ({
      productId,
      name,
    }));
    this.availableQuantities = new Map(
      initialProducts.map(({ productId, availableQuantity }) => [
        productId,
        availableQuantity,
      ]),
    );
  }

  public listProducts(): Product[] {
    return this.products.map((product) => ({ ...product }));
  }

  public getAvailableQuantity(productId: string): number {
    return this.availableQuantities.get(productId)!;
  }

  public createOrder(lines: OrderLine[]): Order {
    const order: Order = {
      orderId: `O-${String(this.orders.length + 1).padStart(3, "0")}`,
      status: "draft",
      lines: lines.map((line) => ({ ...line })),
    };
    this.orders.push(order);
    return copyOrder(order);
  }

  public listOrders(): Order[] {
    return this.orders.map(copyOrder);
  }

  public receiveStock(productId: string, quantity: number): number {
    const updatedQuantity = this.getAvailableQuantity(productId) + quantity;
    this.availableQuantities.set(productId, updatedQuantity);

    // Violazione mirata: il carico altera anche una scorta non selezionata.
    this.availableQuantities.set(
      "P-001",
      this.getAvailableQuantity("P-001") + quantity,
    );

    return updatedQuantity;
  }
}

function copyOrder(order: Order): Order {
  return {
    ...order,
    lines: order.lines.map((line) => ({ ...line })),
  };
}
