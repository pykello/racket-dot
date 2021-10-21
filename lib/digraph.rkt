#lang racket

(require "dot.rkt")
(require pict)

(provide (contract-out
          [make-vertex (->* (string?) (#:shape (or/c pict? string?)) vertex?)]
          [make-edge (-> vertex? vertex? edge?)]
          [digraph->dot (-> digraph? string?)]
          [digraph->pict (-> digraph? pict?)]
          [digraph-node-picts (-> digraph? hash?)])
         make-digraph
         (struct-out digraph)
         (struct-out vertex)
         (struct-out edge)
         (struct-out subgraph))

(struct digraph (objects attrs))
(struct vertex (name label shape attrs))
(struct edge (nodes attrs))
(struct subgraph (label objects attrs))

(define default-shape "none")

(define (make-vertex label #:shape [shape default-shape])
  (define id (random 1 4294967087))
  (define name (string-append "n_" (number->string id)))
  (define attrs (make-immutable-hash))
  (vertex name label shape attrs))

(define (make-edge n1 n2)
  (define nodes (list (vertex-name n1) (vertex-name n2)))
  (define attrs (make-immutable-hash))
  (edge nodes attrs))

(define make-digraph 
  (make-keyword-procedure
    (lambda (kws kw-args . d)
      (define defs (car d))
      (define attrs (make-immutable-hash (map cons kws kw-args)))
      (digraph (map make-object defs) attrs))))

(define (make-object def)
  (cond
    [(or (vertex? def)
         (edge? def)
         (subgraph? def)) def]
    [(string? def) (cond
                     [(string-contains? def "->") (string->edge def)]
                     [else                        (string->vertex def)])]
    [(list? def) (cond
                   [(empty? def) 0]
                   [(eq? (first def) `subgraph)  (list->subgraph def)]
                   [(list? (first def))          (list->edge def)]
                   [(eq? (first def) `edge)      (list->edge (cdr def))]
                   [(eq? (first def) `same-rank) (cdr def)]
                   [else                         (list->vertex def)])]))

;; string->object functions

(define (string->vertex s)
  (vertex s s default-shape (make-immutable-hash)))

(define (string->edge s)
  (edge (string-split s #rx"[ ]*->[ ]*") (make-immutable-hash)))

;; list->object functions

(define (list->edge lst)
  (define nodes (first lst))
  (define-values (attrs rest) (list->attrs (cdr lst)))
  (edge nodes attrs))

(define (list->vertex lst)
  (define-values (attrs rest) (list->attrs (cdr lst)))
  (define name (first lst))
  (define label (hash-ref attrs `#:label name))
  (define shape (hash-ref attrs `#:shape default-shape))
  (define other-attrs
    (hash-remove-multi attrs `(#:label #:shape))) 
  (vertex name label shape other-attrs))

(define (list->subgraph def)
  (define-values (attrs rest) (list->attrs (cdr def)))
  (define name (first rest))
  (define defs (second rest))
  (subgraph name (map make-object defs) attrs))

(define (list->attrs lst)
  (define (aux lst attrs rest)
    (cond
      [(empty? lst)
       (values (make-immutable-hash attrs) (reverse rest))]

      [(keyword? (first lst))
       (aux (cddr lst)
            (cons (cons (first lst) (second lst)) attrs)
            rest)]

      [else
       (aux (cdr lst)
            attrs
            (cons (first lst) rest))]))
  (aux lst `() `()))

;; digraph-node-picts

(define (digraph-node-picts d)
  (make-hash
   (for/list ([v (digraph-vertices d)]
              #:when (pict? (vertex-shape v)))
     (cons (vertex-name v) (vertex-shape v)))))

(define (digraph-vertices d)
  (find-vertices (digraph-objects d)))

(define (subgraph-vertices d)
  (find-vertices (subgraph-objects d)))

(define (find-vertices objs)
  (define outer-vertices (filter vertex? objs))
  (define subgraphs (filter subgraph? objs))
  (define nested-vertices (map subgraph-vertices subgraphs))
  (append outer-vertices (apply append nested-vertices)))

;; digraph->pict

(define (digraph->pict d)
  (dot->pict (digraph->dot d)
             #:node-picts (digraph-node-picts d)))

;; digraph->dot

(define (digraph->dot d)
  (define defs (objects->dot (digraph-objects d)))
  (define attrs (hash->list (digraph-attrs d)))
  (string-append "digraph {\n"
                 (string-join (map property->string attrs) "\n" #:after-last "\n")
                 (indent 4 defs)
                 "\n}"))

(define (indent n s)
  (define lines (string-split s "\n"))
  (define line-prefix (repeat n " "))
  (define indented-lines
    (map (curry string-append line-prefix) lines))
  (string-join indented-lines "\n"))

(define (repeat n s)
  (apply string-append
         (for/list ([x (in-range n)])
           s)))

(define (objects->dot objs)
  (string-join (map object->dot objs) "\n"))

(define (object->dot obj)
  (cond [(vertex? obj) (vertex->dot obj)]
        [(edge? obj) (edge->dot obj)]
        [(subgraph? obj) (subgraph->dot obj)]
        [(list? obj) (rank->dot obj)]
        [else ""]))

(define (subgraph->dot d)
  (define defs (objects->dot (subgraph-objects d)))
  (define attrs (hash->list (subgraph-attrs d)))
  (string-append "subgraph "
                 "cluster_" (number->string (random 1 32000000))
                 " {\n"
                 "label=" (quote-string (subgraph-label d)) "\n"
                 (string-join (map property->string attrs) "\n")
                 "\n"
                 (indent 4 defs)
                 "\n}"))

(define (vertex->dot v)
  (match v
    [(vertex name label shape attrs)
     (define shape-str (if (pict? shape)
                           default-shape
                           shape))
     (define basic-properties `((#:label . ,label)
                                (#:shape . ,shape-str)))
     (define size-properties
       (cond
         [(pict? shape) `((#:fixedsize . "true")
                          (#:height . ,(number->string (/ (pict-height shape) 72.)))
                          (#:width . ,(number->string (/ (pict-width shape) 72.))))]
         [else `()]))

     (define other-properties (hash->list attrs))

     (define properties (append basic-properties size-properties other-properties))
     (string-append name (properties->string properties))]))

(define (edge->dot e)
  (define attrs (edge-attrs e))
  (string-append
   (string-join (edge-nodes e) " -> ")
   (properties->string (hash->list attrs))))

(define (rank->dot e)
  (string-append
    "{\n"
    "rank=same\n"
    "ordering=out\n"
    (string-join e "\n") "\n"
    (string-join e " -> ") "[style=invis]"
    "}"))

(define (properties->string ps)
  (string-join (map property->string ps) ","
               #:before-first "["
               #:after-last   "]"))

(define (property->string p)
  (define label (keyword->string (car p)))
  (string-append label "=" (quote-string (value->string (cdr p)))))

(define (value->string v)
  (cond
    [(eq? v #t) "true"]
    [(eq? v #f) "false"]
    [else v]))

(define (quote-string s)
  (string-append "\"" (string-replace s "\"" "\\\"") "\""))

(define (hash-remove-multi h keys)
  (foldr (λ (v l) (hash-remove l v)) h keys))
