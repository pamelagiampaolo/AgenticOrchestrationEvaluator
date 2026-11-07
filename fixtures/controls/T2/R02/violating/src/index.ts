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

// Violazione mirata: tutte le istanze leggono e modificano la stessa mappa.
const sharedAvailableQuantities = new Map<string, number>();

/** Inventario minimo con scorte erroneamente condivise tra le istanze. */
export class InventoryManagement {
  private readonly products: Product[];
  private readonly orders: Order[] = [];

  public constructor(initialProducts: InitialProduct[]) {
    this.products = initialProducts.map(({ productId, name }) => ({
      productId,
      name,
    }));
    sharedAvailableQuantities.clear();
    for (const { productId, availableQuantity } of initialProducts) {
      sharedAvailableQuantities.set(productId, availableQuantity);
    }
  }

  public listProducts(): Product[] {
    return this.products.map((product) => ({ ...product }));
  }

  public getAvailableQuantity(productId: string): number {
    return sharedAvailableQuantities.get(productId)!;
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
    if (!Number.isSafeInteger(quantity) || quantity <= 0) {
      throw new InventoryManagementError("INVALID_QUANTITY");
    }

    const updatedQuantity = this.getAvailableQuantity(productId) + quantity;
    sharedAvailableQuantities.set(productId, updatedQuantity);
    return updatedQuantity;
  }
}

function copyOrder(order: Order): Order {
  return {
    ...order,
    lines: order.lines.map((line) => ({ ...line })),
  };
}
