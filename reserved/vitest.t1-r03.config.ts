export default {
  test: {
    environment: "node",
    include: ["reserved/t1-r03.test.ts"],
    passWithNoTests: false,
    fileParallelism: false,
  },
};
