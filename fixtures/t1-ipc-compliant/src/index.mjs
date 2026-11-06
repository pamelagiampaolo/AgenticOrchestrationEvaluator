export class InventoryManagement {
  constructor(products) {
    this.products = products.map((product) => ({ ...product }));
  }
  findProductsBelowStock(threshold) {
    return this.products.filter((product) => product.availableQuantity < threshold).map((product) => ({ ...product })).sort((left, right) => left.productId.localeCompare(right.productId));
  }
}
