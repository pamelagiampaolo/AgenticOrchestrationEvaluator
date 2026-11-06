export default {
  test: {
    environment: "node",
    include: ["reserved/t5-r01.test.ts"],
    passWithNoTests: false,
    fileParallelism: false,
    globals: true,
  },
};
