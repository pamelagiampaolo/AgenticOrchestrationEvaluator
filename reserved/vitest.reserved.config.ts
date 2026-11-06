export default {
  test: {
    environment: "node",
    include: ["reserved/smoke.test.ts"],
    passWithNoTests: false,
    fileParallelism: false,
    globals: true,
  },
};
