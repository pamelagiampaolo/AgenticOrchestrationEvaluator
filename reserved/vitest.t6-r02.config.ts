export default {
  test: {
    environment: "node",
    include: ["reserved/t6-r02.test.ts"],
    passWithNoTests: false,
    fileParallelism: false,
  },
};
