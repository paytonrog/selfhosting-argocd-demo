import express from "express";
import { NativeConnection, Worker } from "@temporalio/worker";
import * as activities from "./activities/sayHello";

async function startHealthServer() {
  const app = express();
  app.get("/", (_req, res) => res.status(200).send("ok"));
  app.get("/healthz", (_req, res) => res.status(200).send("ok"));
  const port = Number(process.env.PORT || 8080);
  app.listen(port, () => console.log(`health server listening on ${port}`));
}

async function run() {
  await startHealthServer();

  const address = process.env.TEMPORAL_ADDRESS || "temporal-frontend.temporal.svc.cluster.local:7233";
  const namespace = process.env.TEMPORAL_NAMESPACE || "default";
  const taskQueue = process.env.TEMPORAL_TASK_QUEUE || "sample-task-queue";

  const connection = await NativeConnection.connect({ address });
  const worker = await Worker.create({
    connection,
    namespace,
    taskQueue,
    workflowsPath: require.resolve("./workflows/sampleWorkflow"),
    activities,
  });

  console.log(`Temporal worker starting (namespace=${namespace}, taskQueue=${taskQueue}, address=${address})`);
  await worker.run();
}

run().catch((err) => {
  console.error(err);
  process.exit(1);
});