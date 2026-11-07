export default {
  test: {
    environment: "node",
    include: ["reserved/t3-r02.test.ts"],
    passWithNoTests: false,
    fileParallelism: false,
  },
};
