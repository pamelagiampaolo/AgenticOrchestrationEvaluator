export default {
  test: {
    environment: "node",
    include: ["reserved/t4-r03.test.ts"],
    passWithNoTests: false,
    fileParallelism: false,
  },
};
