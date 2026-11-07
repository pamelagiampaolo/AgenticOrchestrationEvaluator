export default {
  test: {
    environment: "node",
    include: ["reserved/t4-r01.test.ts"],
    passWithNoTests: false,
    fileParallelism: false,
  },
};
