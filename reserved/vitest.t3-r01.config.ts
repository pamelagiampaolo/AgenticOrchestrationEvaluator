export default {
  test: {
    environment: "node",
    include: ["reserved/t3-r01.test.ts"],
    passWithNoTests: false,
    fileParallelism: false,
  },
};
