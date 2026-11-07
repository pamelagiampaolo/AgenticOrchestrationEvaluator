export default {
  test: {
    environment: "node",
    include: ["reserved/t1-r01.test.ts"],
    passWithNoTests: false,
    fileParallelism: false,
  },
};
