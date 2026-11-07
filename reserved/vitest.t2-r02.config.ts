export default {
  test: {
    environment: "node",
    include: ["reserved/t2-r02.test.ts"],
    passWithNoTests: false,
    fileParallelism: false,
  },
};
