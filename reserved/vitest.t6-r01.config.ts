export default {
  test: {
    environment: "node",
    include: ["reserved/t6-r01.test.ts"],
    passWithNoTests: false,
    fileParallelism: false,
  },
};
