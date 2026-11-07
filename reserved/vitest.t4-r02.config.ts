export default {
  test: {
    environment: "node",
    include: ["reserved/t4-r02.test.ts"],
    passWithNoTests: false,
    fileParallelism: false,
  },
};
