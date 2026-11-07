export default {
  test: {
    environment: "node",
    include: ["reserved/t2-r01.test.ts"],
    passWithNoTests: false,
    fileParallelism: false,
  },
};
