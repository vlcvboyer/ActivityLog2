#lang racket/base
;; trends-bw.rkt -- bodyweight trend chart
;;
;; This file is part of ActivityLog2, an fitness activity tracker
;; Copyright (C) 2016 Alex Harsanyi (AlexHarsanyi@gmail.com)
;;
;; This program is free software: you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by the Free
;; Software Foundation, either version 3 of the License, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
;; FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
;; more details.


(require
 db
 plot
 racket/class
 racket/match
 racket/gui/base
 "database.rkt"
 "trends-chart.rkt"
 "icon-resources.rkt"
 "widgets.rkt"
 "plot-hack.rkt")

(provide bw-trends-chart%)

(struct bw-params tc-params (start-date end-date group-by))

(define bw-chart-settings%
  (class al-edit-dialog%
    (init-field database
                [default-name "Trends"]
                [default-title "Trends Chart"])

    (super-new [title "Chart Settings"]
               [icon edit-icon]
               [min-height 10]
               [tablet-friendly? #t])

    (define name-field
      (let ((p (make-horizontal-pane (send this get-client-pane) #f)))
        (send p spacing al-dlg-item-spacing)
        (new text-field% [parent p] [label "Name "])))
    (send name-field set-value default-name)

    (define title-field
      (let ((p (make-horizontal-pane (send this get-client-pane) #f)))
        (send p spacing al-dlg-item-spacing)
        (new text-field% [parent p] [label "Title "])))
    (send title-field set-value default-title)

    (define date-range-selector
      (let ((p (make-horizontal-pane (send this get-client-pane) #f)))
        (send p spacing al-dlg-item-spacing)
        (new date-range-selector% [parent p])))

    (define group-by-choice
      (let ((p (make-horizontal-pane (send this get-client-pane) #f)))
        (send p spacing al-dlg-item-spacing)
        (new choice% [parent p] [label "Group By "]
             [choices '("Week" "Month" "Year")])))

    (define/public (get-restore-data)
      (list
       (send name-field get-value)
       (send title-field get-value)
       (send date-range-selector get-restore-data)
       (send group-by-choice get-selection)))

    (define/public (restore-from data)
      (when database
        (send date-range-selector set-seasons (db-get-seasons database)))
      (match-define (list d0 d1 d2 d3) data)
      (send name-field set-value d0)
      (send title-field set-value d1)
      (send date-range-selector restore-from d2)
      (send group-by-choice set-selection d3))

    (define/public (show-dialog parent)
      (when database
        (send date-range-selector set-seasons (db-get-seasons database)))
      (if (send this do-edit parent)
          (get-settings)
          #f))

    (define/public (get-settings)
      (let ((dr (send date-range-selector get-selection)))
        (if dr
            (let ((start-date (car dr))
                  (end-date (cdr dr)))
              (when (eqv? start-date 0)
                (set! start-date (get-true-min-start-date database)))
              (bw-params
               (send name-field get-value)
               (send title-field get-value)
               start-date
               end-date
               (send group-by-choice get-selection)))
            #f)))
    ))

(define (get-data db sql-query start-date end-date group-by)
  (let* ((filter-width (* 24 60 60 (case group-by ((0) 7) ((1) 30) ((2) 365))))
         (filter (make-low-pass-filter filter-width #f)))
    (for/list (([timestamp bw] (in-query db sql-query start-date end-date)))
      (filter (vector timestamp bw)))))

(define *sea-green* '(#x2e #x8b #x57))

(define bw-trends-chart%
  (class trends-chart%
    (init-field database)
    (super-new)

    (define data-valid? #f)

    (define bw-query
      (virtual-statement
       (lambda (dbsys)
         "select timestamp, body_weight as bw
            from ATHLETE_METRICS
           where timestamp between ? and ?")))

    (define bw-data #f)                 ; fetched from the database

    (define/override (make-settings-dialog)
      (new bw-chart-settings%
           [default-name "BodyWeight"]
           [default-title "Body Weight"]
           [database database]))

    (define/override (invalidate-data)
      (set! data-valid? #f))

    (define/override (put-plot-snip canvas)
      (maybe-fetch-data)
      (when data-valid?
        (parameterize ([plot-x-ticks (pmc-date-ticks)]
                       [plot-x-label #f]
                       [plot-y-label "Bodyweight"])
          (plot-snip/hack
           canvas
           (list (tick-grid) (lines bw-data #:color *sea-green* #:width 3.0))))))

    (define (maybe-fetch-data)
      (unless data-valid?
        (let ((params (send this get-params)))
          (when params
            (let ((start (bw-params-start-date params))
                  (end (bw-params-end-date params))
                  (group-by (bw-params-group-by params)))
              (set! bw-data (get-data database bw-query start end group-by))
              (set! data-valid? (> (length bw-data) 0)))))))

    ))