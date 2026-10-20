source("R/analysis.R")

out <- tempfile()

dir.create(out)

r <- run_analysis(normalizePath("."), out)

stopifnot(length(r) > 0, file.exists(out))

stopifnot(r$rows == 1336, r$train_rows + r$test_rows == 1336, !"enrollee_id" %in% names(read.csv("data/job_change.csv")))

toy <- data.frame(c = c("a", "a", "b"), x = c(1, NA, 3))

p <- prepare(toy, data.frame(c = "new", x = 100), c("c", "x"))

stopifnot(all(is.finite(p$test)))

cat("Validation passed\n")

