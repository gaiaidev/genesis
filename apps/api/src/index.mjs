import express from "express";
import health from "./routes/health.mjs";
const app = express();
const PORT = process.env.PORT || 3002;
app.get("/health", health);
app.listen(PORT, () => console.log(`[api] listening on ${PORT}`));
export default app;
