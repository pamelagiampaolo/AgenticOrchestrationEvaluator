export type { InventoryRepository, Order, OrderRepository, Product, ProductRepository } from "./contracts.js";
export { InMemoryInventoryRepository, InMemoryOrderRepository, InMemoryProductRepository } from "./repositories.js";
export { createInventoryManagementWithRepositories, InventoryManagement } from "./inventory-management.js";
