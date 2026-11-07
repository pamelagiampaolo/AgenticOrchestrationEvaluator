export default {
  test: {
    environment: "node",
    include: ["reserved/t3-r03.test.ts"],
    passWithNoTests: false,
    fileParallelism: false,
  },
};
