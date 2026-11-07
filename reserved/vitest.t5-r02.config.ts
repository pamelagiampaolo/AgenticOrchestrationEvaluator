export default {
  test: {
    environment: "node",
    include: ["reserved/t5-r02.test.ts"],
    passWithNoTests: false,
    fileParallelism: false,
  },
};
