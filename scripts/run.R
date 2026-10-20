args <- commandArgs(trailingOnly = TRUE)

script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1])

root <- normalizePath(file.path(dirname(script), ".."))

source(file.path(root, "R", "analysis.R"))

out <- file.path(root, "results")

dir.create(out, showWarnings = FALSE)

result <- run_analysis(root, out)

jsonlite::write_json(result, file.path(out, "metrics.json"), pretty = TRUE, auto_unbox = TRUE, 
    digits = 12, na = "null")

print(result)

