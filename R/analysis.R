split_rows <- function(y, seed = 121, p = 0.7) {
    set.seed(seed)
    sort(unlist(lapply(split(seq_along(y), y), function(i) sample(i, floor(length(i) * p)))))
}

score <- function(actual, pred, prob = NULL) {
    levels_y <- levels(actual)
    cm <- table(actual = factor(actual, levels_y), predicted = factor(pred, levels_y))
    result <- list(accuracy = mean(actual == pred), confusion = unclass(cm))
    if (length(levels_y) == 2) {
        positive <- levels_y[2]
        tp <- sum(actual == positive & pred == positive)
        fp <- sum(actual != positive & pred == positive)
        fn <- sum(actual == positive & pred != positive)
        tn <- sum(actual != positive & pred != positive)
        result$recall <- tp/(tp + fn)
        result$precision <- if (tp + fp) 
            tp/(tp + fp)
        else 0
        result$balanced_accuracy <- (tp/(tp + fn) + tn/(tn + fp))/2
        if (!is.null(prob)) {
            y <- actual == positive
            result$roc_auc <- (sum(rank(prob)[y]) - sum(y) * (sum(y) + 1)/2)/(sum(y) * sum(!y))
        }
    }
    result
}

prepare <- function(train, test, columns) {
    for (k in columns) {
        if (is.numeric(train[[k]])) {
            value <- median(train[[k]], na.rm = TRUE)
            train[[k]][is.na(train[[k]])] <- value
            test[[k]][is.na(test[[k]])] <- value
        }
        else {
            a <- as.character(train[[k]])
            b <- as.character(test[[k]])
            valid <- a[!is.na(a) & a != ""]
            mode <- names(sort(table(valid), decreasing = TRUE))[1]
            a[is.na(a) | a == ""] <- mode
            levels_a <- sort(unique(a))
            b[is.na(b) | !b %in% levels_a] <- mode
            train[[k]] <- factor(a, levels_a)
            test[[k]] <- factor(b, levels_a)
        }
    }
    x <- model.matrix(~., train[, columns, drop = FALSE])
    xt <- model.matrix(~., test[, columns, drop = FALSE])
    x <- x[, colnames(x) != "(Intercept)", drop = FALSE]
    xt <- xt[, colnames(xt) != "(Intercept)", drop = FALSE]
    keep <- apply(x, 2, sd) > 1e-08
    x <- x[, keep, drop = FALSE]
    xt <- xt[, keep, drop = FALSE]
    q <- qr(scale(x, center = TRUE, scale = FALSE))
    keep <- sort(q$pivot[seq_len(q$rank)])
    list(train = x[, keep, drop = FALSE], test = xt[, keep, drop = FALSE])
}

run_analysis <- function(root, out) {
    d <- read.csv(file.path(root, "data/job_change.csv"), stringsAsFactors = FALSE)
    d <- d[d$city == "city_114", ]
    d$target <- factor(d$target, levels = c(0, 1))
    d$training_hours <- log1p(d$training_hours)
    columns <- c("relevent_experience", "enrolled_university", "education_level", "major_discipline", 
        "experience", "company_size", "company_type", "last_new_job", "training_hours")
    idx <- split_rows(d$target, 121, 0.8)
    train <- d[idx, ]
    test <- d[-idx, ]
    missing_counts <- vapply(train[,columns], function(v) sum(is.na(v) | as.character(v)==""), integer(1))
    write.csv(data.frame(feature=names(missing_counts), missing_training_rows=missing_counts), file.path(out,"training-missingness.csv"),row.names=FALSE)
    curves <- list()
    x <- prepare(train, test, columns)
    y <- train$target
    set.seed(530306)
    groups <- split(seq_along(y), y)
    balanced <- unlist(lapply(groups, function(i) c(i, sample(i, max(lengths(groups)) - length(i), 
        replace = TRUE))))
    results <- list(scope = "city_114; retrospective job-change intent", rows = nrow(d), 
        train_rows = nrow(train), test_rows = nrow(test), test_positive = sum(test$target == 
            "1"), majority_accuracy = max(table(test$target))/nrow(test), positive_class = "1 = recorded job-change intent", 
        predictors = ncol(x$train))
    for (sampling in c("original", "oversampled")) {
        rows <- if (sampling == "original") 
            seq_along(y)
        else balanced
        tr <- data.frame(target = y[rows], x$train[rows, , drop = FALSE])
        te <- data.frame(x$test)
        lda <- MASS::lda(target ~ ., tr)
        pr <- predict(lda, te)
        results[[paste0("LDA_", sampling)]] <- score(test$target, pr$class, pr$posterior[, 
            "1"])
        curves[[paste0("LDA_",sampling)]] <- pr$posterior[,"1"]
        fit <- glm(target ~ ., tr, family = binomial())
        prob <- predict(fit, te, type = "response")
        curves[[paste0("Logistic_",sampling)]] <- prob
        results[[paste0("Logistic_", sampling)]] <- score(test$target, factor(ifelse(prob >= 
            0.5, 1, 0), levels = c(0, 1)), prob)
    }
    png(file.path(out,"evaluation.png"),width=1200,height=600)
    par(mfrow=c(1,2))
    barplot(rbind(table(train$target),table(test$target)),beside=TRUE,col=c("#246b83","#ea9546"),names.arg=c("No change intent","Change intent"),legend.text=c("Training","Test"),main="Class balance",ylab="Records")
    plot(c(0,1),c(0,1),type="n",xlab="False positive rate",ylab="True positive rate",main="Held-out ROC curves")
    abline(0,1,col="grey70",lty=2)
    y_test <- test$target=="1"
    for(i in seq_along(curves)) {prob<-curves[[i]];thresholds<-c(Inf,sort(unique(prob),decreasing=TRUE),-Inf);tpr<-vapply(thresholds,function(t)mean(prob[y_test]>=t),numeric(1));fpr<-vapply(thresholds,function(t)mean(prob[!y_test]>=t),numeric(1));lines(fpr,tpr,col=i,lwd=2)}
    legend("bottomright",legend=gsub("_"," ",names(curves)),col=seq_along(curves),lwd=2,cex=.75)
    dev.off()
    results
}

