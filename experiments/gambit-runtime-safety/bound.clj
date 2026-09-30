(ns native-bound
  (:require [babashka.process :as process]))

(defn limit-ms [text]
  (when (and text (re-matches #"[1-9][0-9]{0,5}" text))
    (* 1000 (parse-long text))))

(defn stop-tree! [child]
  (let [root (.toHandle (:proc child))
        handles (with-open [descendants (.descendants root)]
                  (conj (vec (iterator-seq (.iterator descendants))) root))]
    (doseq [handle handles]
      (.destroy handle))
    (Thread/sleep 2000)
    (doseq [handle handles :when (.isAlive handle)]
      (.destroyForcibly handle))
    @child))

(let [[seconds & command] *command-line-args*
      milliseconds (limit-ms seconds)]
  (when-not (and milliseconds (seq command))
    (binding [*out* *err*]
      (println "Usage: native-bound.clj SECONDS COMMAND... (1..999999)"))
    (System/exit 2))
  (let [child (process/process {:cmd (vec command) :inherit true})
        result (deref child milliseconds ::deadline)]
    (System/exit
     (if (= ::deadline result)
       (do
         (binding [*out* *err*]
           (println "DEADLINE after" seconds "seconds"))
         (stop-tree! child)
         124)
       (:exit result)))))
