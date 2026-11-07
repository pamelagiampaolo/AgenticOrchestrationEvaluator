/** Prodotto esposto dal catalogo. */
export type Product = { productId: string; name: string };

/** Prodotto con la quantita iniziale disponibile. */
export type InitialProduct = Product & { availableQuantity: number };

/** Prodotto con lo stato operativo. */
export type ProductWithStatus = Product & {
  status: "active" | "suspended";
};

/** Riga di un ordine. */
export type OrderLine = { productId: string; quantity: number };

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

/** Inventario minimo con conferma erroneamente non atomica. */
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
    const product = this.requireProduct(productId);
    this.productStatuses.set(productId, "suspended");
    return { ...product, status: "suspended" };
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

    // Violazione mirata: ogni riga valida viene applicata prima delle successive.
    for (const line of order.lines) {
      if (this.productStatuses.get(line.productId) === "suspended") {
        throw new InventoryManagementError("PRODUCT_SUSPENDED");
      }
      const availableQuantity = this.getAvailableQuantity(line.productId);
      if (availableQuantity < line.quantity) {
        throw new InventoryManagementError("INSUFFICIENT_STOCK");
      }
      this.availableQuantities.set(
        line.productId,
        availableQuantity - line.quantity,
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

  private requireProduct(productId: string): Product {
    const product = this.products.find((value) => value.productId === productId);
    if (product === undefined) {
      throw new InventoryManagementError("PRODUCT_NOT_FOUND");
    }
    return product;
  }
}

function copyOrder(order: Order): Order {
  return { ...order, lines: order.lines.map((line) => ({ ...line })) };
}
