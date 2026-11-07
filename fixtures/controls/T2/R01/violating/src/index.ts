/** Prodotto esposto dal catalogo. */
export type Product = {
  productId: string;
  name: string;
};

/** Prodotto con la quantita iniziale disponibile. */
export type InitialProduct = Product & {
  availableQuantity: number;
};

/** Riga di un ordine in bozza. */
export type OrderLine = {
  productId: string;
  quantity: number;
};

/** Ordine minimo osservabile dai controlli T2. */
export type Order = {
  orderId: string;
  status: "draft";
  lines: OrderLine[];
};

class InventoryManagementError extends Error {
  public constructor(public readonly code: string) {
    super(code);
  }
}

/** Inventario minimo con la violazione mirata dell'atomicita di T2-R01. */
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

  /** Modifica erroneamente la scorta prima di validare la quantita. */
  public receiveStock(productId: string, quantity: number): number {
    const updatedQuantity = this.getAvailableQuantity(productId) + quantity;
    this.availableQuantities.set(productId, updatedQuantity);

    if (!Number.isSafeInteger(quantity) || quantity <= 0) {
      throw new InventoryManagementError("INVALID_QUANTITY");
    }

    return updatedQuantity;
  }
}

function copyOrder(order: Order): Order {
  return {
    ...order,
    lines: order.lines.map((line) => ({ ...line })),
  };
}
