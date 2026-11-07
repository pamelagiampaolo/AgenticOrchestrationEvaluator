/** Prodotto esposto dal catalogo. */
export type Product = {
  productId: string;
  name: string;
};

/** Prodotto con la quantita iniziale disponibile. */
export type InitialProduct = Product & {
  availableQuantity: number;
};

/** Prodotto con lo stato operativo. */
export type ProductWithStatus = Product & {
  status: "active" | "suspended";
};

/** Riga di un ordine. */
export type OrderLine = {
  productId: string;
  quantity: number;
};

/** Ordine osservabile dai controlli T4. */
export type Order = {
  orderId: string;
  status: "draft" | "confirmed";
  lines: OrderLine[];
};

class InventoryManagementError extends Error {
  public constructor(public readonly code: string) {
    super(code);
  }
}

/** Inventario minimo che valida l'esistenza prima di sospendere un prodotto. */
export class InventoryManagement {
  private readonly products: Product[];
  private readonly productStatuses: Map<string, ProductWithStatus["status"]>;
  private readonly availableQuantities: Map<string, number>;
  private readonly orders = new Map<string, Order>();
  private nextOrderNumber = 1;

  public constructor(initialProducts: InitialProduct[]) {
    this.products = initialProducts.map(({ productId, name }) => ({
      productId,
      name,
    }));
    this.productStatuses = new Map(
      initialProducts.map(({ productId }) => [productId, "active"]),
    );
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

  public listProductsWithStatus(): ProductWithStatus[] {
    return this.products.map((product) => ({
      ...product,
      status: this.productStatuses.get(product.productId)!,
    }));
  }

  public getAvailableQuantity(productId: string): number {
    return this.availableQuantities.get(productId)!;
  }

  public suspendProduct(productId: string): ProductWithStatus {
    const product = this.products.find((value) => value.productId === productId);
    if (product === undefined) {
      throw new InventoryManagementError("PRODUCT_NOT_FOUND");
    }
    if (this.productStatuses.get(productId) === "suspended") {
      throw new InventoryManagementError("PRODUCT_ALREADY_SUSPENDED");
    }
    this.productStatuses.set(productId, "suspended");
    return { ...product, status: "suspended" };
  }

  public reactivateProduct(productId: string): ProductWithStatus {
    const product = this.products.find((value) => value.productId === productId);
    if (product === undefined) {
      throw new InventoryManagementError("PRODUCT_NOT_FOUND");
    }
    this.productStatuses.set(productId, "active");
    return { ...product, status: "active" };
  }

  public createOrder(lines: OrderLine[]): Order {
    const order: Order = {
      orderId: `O-${String(this.nextOrderNumber++).padStart(3, "0")}`,
      status: "draft",
      lines: lines.map((line) => ({ ...line })),
    };
    this.orders.set(order.orderId, order);
    return copyOrder(order);
  }

  public confirmOrder(orderId: string): Order {
    const order = this.orders.get(orderId)!;
    const requestedQuantities = aggregateQuantities(order.lines);

    for (const productId of requestedQuantities.keys()) {
      if (this.productStatuses.get(productId) === "suspended") {
        throw new InventoryManagementError("PRODUCT_SUSPENDED");
      }
    }
    for (const [productId, quantity] of requestedQuantities) {
      if (this.getAvailableQuantity(productId) < quantity) {
        throw new InventoryManagementError("INSUFFICIENT_STOCK");
      }
    }
    for (const [productId, quantity] of requestedQuantities) {
      this.availableQuantities.set(
        productId,
        this.getAvailableQuantity(productId) - quantity,
      );
    }

    const confirmed: Order = { ...order, status: "confirmed" };
    this.orders.set(orderId, confirmed);
    return copyOrder(confirmed);
  }

  public getOrder(orderId: string): Order {
    return copyOrder(this.orders.get(orderId)!);
  }

  public listOrders(): Order[] {
    return [...this.orders.values()].map(copyOrder);
  }
}

function aggregateQuantities(lines: readonly OrderLine[]): Map<string, number> {
  const quantities = new Map<string, number>();
  for (const line of lines) {
    quantities.set(
      line.productId,
      (quantities.get(line.productId) ?? 0) + line.quantity,
    );
  }
  return quantities;
}

function copyOrder(order: Order): Order {
  return {
    ...order,
    lines: order.lines.map((line) => ({ ...line })),
  };
}
