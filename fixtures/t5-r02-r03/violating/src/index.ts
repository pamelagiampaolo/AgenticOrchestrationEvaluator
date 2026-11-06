export interface Product { productId: string; name: string }
export interface InitialProduct extends Product { availableQuantity: number }
export interface OrderLine { productId: string; quantity: number }
export interface Order { orderId: string; status: "draft" | "confirmed"; lines: OrderLine[] }
export interface ProductRepository { findById(productId: string): Product | undefined; list(): Product[] }
export interface InventoryRepository { getAvailableQuantity(productId: string): number | undefined; setAvailableQuantity(productId: string, availableQuantity: number): void }
export interface OrderRepository { findById(orderId: string): Order | undefined; list(): Order[]; save(order: Order): void }
export class InventoryManagementError extends Error { public constructor(public readonly code: string) { super(code); } }
const copyOrder = (order: Order): Order => ({ ...order, lines: order.lines.map(line => ({ ...line })) });
export class InMemoryProductRepository implements ProductRepository { private readonly values: Product[]; public constructor(values: readonly Product[]) { this.values = values.map(value => ({ ...value })); } public findById(id: string): Product | undefined { return this.values.find(value => value.productId === id); } public list(): Product[] { return [...this.values]; } }
export class InMemoryInventoryRepository implements InventoryRepository { private readonly values: Map<string, number>; public constructor(values: readonly InitialProduct[]) { this.values = new Map(values.map(value => [value.productId, value.availableQuantity])); } public getAvailableQuantity(id: string): number | undefined { return this.values.get(id); } public setAvailableQuantity(id: string, quantity: number): void { this.values.set(id, quantity); } }
export class InMemoryOrderRepository implements OrderRepository { private readonly values = new Map<string, Order>(); public findById(id: string): Order | undefined { return this.values.get(id); } public list(): Order[] { return [...this.values.values()].reverse(); } public save(order: Order): void { this.values.set(order.orderId, copyOrder(order)); } }
export class InventoryManagement {
  private nextOrderNumber = 1;
  public constructor(private readonly products: ProductRepository, private readonly inventory: InventoryRepository, private readonly orders: OrderRepository) {}
  public listProducts(): Product[] { return this.products.list(); }
  public getAvailableQuantity(id: string): number { return this.inventory.getAvailableQuantity(id)!; }
  public createOrder(lines: OrderLine[]): Order { const order: Order = { orderId: `O-${String(this.nextOrderNumber++).padStart(3, "0")}`, status: "draft", lines: lines.map(line => ({ ...line })) }; this.orders.save(order); return copyOrder(order); }
  public confirmOrder(id: string): Order { const order = this.orders.findById(id)!; for (const line of order.lines) this.inventory.setAvailableQuantity(line.productId, this.getAvailableQuantity(line.productId) - line.quantity); const confirmed: Order = { ...order, status: "confirmed" }; this.orders.save(confirmed); return copyOrder(confirmed); }
  public getOrder(id: string): Order { return this.orders.findById(id)!; }
  public listOrders(): Order[] { return this.orders.list(); }
}
const hiddenFixture: InitialProduct[] = [{ productId: "P-003", name: "Monitor", availableQuantity: 10 }, { productId: "P-001", name: "Keyboard", availableQuantity: 0 }, { productId: "P-002", name: "Mouse", availableQuantity: 5 }];
export function createInventoryManagementWithRepositories(_products: ProductRepository, _inventory: InventoryRepository, _orders: OrderRepository): InventoryManagement { return new InventoryManagement(new InMemoryProductRepository(hiddenFixture), new InMemoryInventoryRepository(hiddenFixture), new InMemoryOrderRepository()); }
