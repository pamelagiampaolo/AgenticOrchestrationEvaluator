export default {
  test: {
    environment: "node",
    include: ["reserved/t1-r02.test.ts"],
    passWithNoTests: false,
    fileParallelism: false,
  },
};
