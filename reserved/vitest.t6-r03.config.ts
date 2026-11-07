export default {
  test: {
    environment: "node",
    include: ["reserved/t6-r03.test.ts"],
    passWithNoTests: false,
    fileParallelism: false,
  },
};
