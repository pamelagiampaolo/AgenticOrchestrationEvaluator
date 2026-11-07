/** Prodotto esposto dal catalogo. */
export type Product = {
  productId: string;
  name: string;
};

/** Prodotto con la quantita iniziale disponibile. */
export type InitialProduct = Product & {
  availableQuantity: number;
};

/** Inventario minimo con la violazione mirata del catalogo vuoto di T1-R02. */
export class InventoryManagement {
  private readonly products: InitialProduct[];

  public constructor(initialProducts: InitialProduct[]) {
    this.products = initialProducts.map((product) => ({ ...product }));
  }

  /** Restituisce erroneamente un prodotto fantasma quando il catalogo e vuoto. */
  public findProductsBelowStock(threshold: number): InitialProduct[] {
    if (this.products.length === 0) {
      return [
        {
          productId: "P-GHOST",
          name: "Prodotto inesistente",
          availableQuantity: 0,
        },
      ];
    }

    return this.products
      .filter((product) => product.availableQuantity < threshold)
      .sort((left, right) => left.productId.localeCompare(right.productId))
      .map((product) => ({ ...product }));
  }
}
