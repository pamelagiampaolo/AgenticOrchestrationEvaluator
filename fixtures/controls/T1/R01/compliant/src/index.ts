/** Prodotto esposto dal catalogo. */
export type Product = {
  productId: string;
  name: string;
};

/** Prodotto con la quantita iniziale disponibile. */
export type InitialProduct = Product & {
  availableQuantity: number;
};

/** Inventario minimo usato per validare il confine stretto di T1-R01. */
export class InventoryManagement {
  private readonly products: InitialProduct[];

  public constructor(initialProducts: InitialProduct[]) {
    this.products = initialProducts.map((product) => ({ ...product }));
  }

  /** Restituisce copie dei prodotti con scorta strettamente inferiore alla soglia. */
  public findProductsBelowStock(threshold: number): InitialProduct[] {
    return this.products
      .filter((product) => product.availableQuantity < threshold)
      .sort((left, right) => left.productId.localeCompare(right.productId))
      .map((product) => ({ ...product }));
  }
}
