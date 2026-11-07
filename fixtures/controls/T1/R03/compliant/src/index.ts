/** Prodotto esposto dal catalogo. */
export type Product = {
  productId: string;
  name: string;
};

/** Prodotto con la quantita iniziale disponibile. */
export type InitialProduct = Product & {
  availableQuantity: number;
};

/** Inventario minimo usato per validare l'isolamento delle letture di T1-R03. */
export class InventoryManagement {
  private readonly products: InitialProduct[];

  public constructor(initialProducts: InitialProduct[]) {
    this.products = initialProducts.map((product) => ({ ...product }));
  }

  /** Restituisce copie indipendenti dei prodotti sotto soglia. */
  public findProductsBelowStock(threshold: number): InitialProduct[] {
    return this.products
      .filter((product) => product.availableQuantity < threshold)
      .sort((left, right) => left.productId.localeCompare(right.productId))
      .map((product) => ({ ...product }));
  }
}
