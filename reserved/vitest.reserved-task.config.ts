const taskId = process.env.RESERVED_TASK_ID;

if (!taskId || !/^T[1-6]$/.test(taskId)) {
  throw new Error("RESERVED_TASK_ID must be one of T1, T2, T3, T4, T5 or T6");
}

export default {
  test: {
    environment: "node",
    include: [`reserved/${taskId.toLowerCase()}-r*.test.ts`],
    passWithNoTests: false,
    fileParallelism: false,
    globals: true,
  },
};
