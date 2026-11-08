// Sonda T5-R01 (forma realistica, attesa conforme): contratti, implementazioni e logica applicativa
// in file separati, riesportati da index.ts.
export type Product = { productId: string; name: string };
export type Order = { orderId: string };

export interface ProductRepository {
  findById(productId: string): Product | undefined;
  list(): Product[];
}
export interface InventoryRepository {
  getAvailableQuantity(productId: string): number | undefined;
  setAvailableQuantity(productId: string, availableQuantity: number): void;
}
export interface OrderRepository {
  findById(orderId: string): Order | undefined;
  list(): Order[];
  save(order: Order): void;
}
