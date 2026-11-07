/** Prodotto esposto dal catalogo. */
export type Product = { productId: string; name: string };

/** Prodotto con la quantita iniziale disponibile. */
export type InitialProduct = Product & { availableQuantity: number };

type FulfillmentStatus =
  | "draft"
  | "waiting"
  | "partially-fulfilled"
  | "fulfilled";

type FulfillmentOrderLine = {
  productId: string;
  requestedQuantity: number;
  fulfilledQuantity: number;
  remainingQuantity: number;
};

type Order = {
  orderId: string;
  status: FulfillmentStatus;
  lines: FulfillmentOrderLine[];
};

class InventoryManagementError extends Error {
  public constructor(public readonly code: string) {
    super(code);
  }
}

/** Inventario minimo che ignora erroneamente l'ultima linea multiprodotto. */
export class InventoryManagement {
  private readonly products: Product[];
  private readonly availableQuantities: Map<string, number>;
  private readonly orders = new Map<string, Order>();
  private nextOrderNumber = 1;

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

  public createOrder(
    lines: Array<{ productId: string; quantity: number }>,
  ): Order {
    const order: Order = {
      orderId: `O-${String(this.nextOrderNumber++).padStart(3, "0")}`,
      status: "draft",
      lines: lines.map(({ productId, quantity }) => ({
        productId,
        requestedQuantity: quantity,
        fulfilledQuantity: 0,
        remainingQuantity: quantity,
      })),
    };
    this.orders.set(order.orderId, order);
    return copyOrder(order);
  }

  public confirmOrder(orderId: string): Order {
    return this.allocateAvailableStock(this.orders.get(orderId)!);
  }

  public fulfillOrder(orderId: string): Order {
    const order = this.orders.get(orderId)!;
    if (order.status === "fulfilled") {
      throw new InventoryManagementError("ORDER_ALREADY_FULFILLED");
    }
    return this.allocateAvailableStock(order);
  }

  public receiveStock(productId: string, quantity: number): number {
    if (!Number.isSafeInteger(quantity) || quantity <= 0) {
      throw new InventoryManagementError("INVALID_QUANTITY");
    }
    const updatedQuantity = this.getAvailableQuantity(productId) + quantity;
    this.availableQuantities.set(productId, updatedQuantity);
    return updatedQuantity;
  }

  public getOrder(orderId: string): Order {
    return copyOrder(this.orders.get(orderId)!);
  }

  public listOrders(): Order[] {
    return [...this.orders.values()].map(copyOrder);
  }

  private allocateAvailableStock(order: Order): Order {
    const linesToAllocate =
      order.lines.length > 1 ? order.lines.slice(0, -1) : order.lines;
    for (const line of linesToAllocate) {
      allocateLine(line, this.availableQuantities);
    }
    order.status = statusFor(order.lines);
    return copyOrder(order);
  }
}

function allocateLine(
  line: FulfillmentOrderLine,
  availableQuantities: Map<string, number>,
): void {
  const availableQuantity = availableQuantities.get(line.productId)!;
  const allocatedQuantity = Math.min(
    availableQuantity,
    line.remainingQuantity,
  );
  line.fulfilledQuantity += allocatedQuantity;
  line.remainingQuantity -= allocatedQuantity;
  availableQuantities.set(
    line.productId,
    availableQuantity - allocatedQuantity,
  );
}

function statusFor(lines: readonly FulfillmentOrderLine[]): FulfillmentStatus {
  return lines.every((line) => line.remainingQuantity === 0)
    ? "fulfilled"
    : lines.some((line) => line.fulfilledQuantity > 0)
      ? "partially-fulfilled"
      : "waiting";
}

function copyOrder(order: Order): Order {
  return { ...order, lines: order.lines.map((line) => ({ ...line })) };
}
