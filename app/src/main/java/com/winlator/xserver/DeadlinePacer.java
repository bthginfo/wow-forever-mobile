package com.winlator.xserver;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.PriorityQueue;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.locks.Condition;
import java.util.concurrent.locks.ReentrantLock;
import java.util.function.Predicate;

/**
 * Hands items to a sink at their deadlines from one thread.
 *
 * <p>The thread blocks while nothing is due: it waits for the earliest deadline and wakes early only when an
 * item with an earlier deadline arrives. A polling pacer would keep a CPU core awake even when the game is idle.
 */
public final class DeadlinePacer<T> {
    public interface Sink<T> {
        void release(T item);
    }

    private static final class Entry<T> {
        final T item;
        final long deadlineNs;
        final long order;

        Entry(T item, long deadlineNs, long order) {
            this.item = item;
            this.deadlineNs = deadlineNs;
            this.order = order;
        }
    }

    private final PriorityQueue<Entry<T>> queue = new PriorityQueue<>(11, (a, b) -> {
        int byDeadline = Long.compare(a.deadlineNs, b.deadlineNs);
        return byDeadline != 0 ? byDeadline : Long.compare(a.order, b.order);
    });
    private final ReentrantLock lock = new ReentrantLock();
    private final Condition changed = lock.newCondition();
    private final Sink<T> sink;
    private final String threadName;
    private Thread thread;
    private long nextOrder;
    private boolean closed;

    public DeadlinePacer(String threadName, Sink<T> sink) {
        this.threadName = threadName;
        this.sink = sink;
    }

    /** Queues {@code item} for release once {@link System#nanoTime()} reaches {@code deadlineNs}. */
    public void schedule(T item, long deadlineNs) {
        lock.lock();
        try {
            if (closed) return;
            Entry<T> entry = new Entry<>(item, deadlineNs, nextOrder++);
            queue.add(entry);
            if (thread == null) start();
            else if (queue.peek() == entry) changed.signal();
        } finally {
            lock.unlock();
        }
    }

    /** Releases every queued item that matches, now and in deadline order, on the calling thread. */
    public void releaseMatching(Predicate<T> match) {
        List<Entry<T>> matched = new ArrayList<>();
        lock.lock();
        try {
            for (Iterator<Entry<T>> it = queue.iterator(); it.hasNext(); ) {
                Entry<T> entry = it.next();
                if (match.test(entry.item)) {
                    matched.add(entry);
                    it.remove();
                }
            }
        } finally {
            lock.unlock();
        }
        matched.sort(queue.comparator());
        for (Entry<T> entry : matched) sink.release(entry.item);
    }

    public int pendingCount() {
        lock.lock();
        try {
            return queue.size();
        } finally {
            lock.unlock();
        }
    }

    /** Stops the thread. Items that are still queued are dropped, as the client that waits for them is gone. */
    public void close() {
        Thread running;
        lock.lock();
        try {
            closed = true;
            queue.clear();
            running = thread;
            changed.signalAll();
        } finally {
            lock.unlock();
        }
        if (running != null) running.interrupt();
    }

    Thread threadForTest() {
        lock.lock();
        try {
            return thread;
        } finally {
            lock.unlock();
        }
    }

    private void start() {
        Thread worker = new Thread(this::run, threadName);
        worker.setDaemon(true);
        worker.setPriority(Thread.MAX_PRIORITY);
        thread = worker;
        worker.start();
    }

    private void run() {
        while (true) {
            T due;
            lock.lock();
            try {
                while (true) {
                    if (closed) return;
                    Entry<T> head = queue.peek();
                    if (head == null) {
                        changed.await();
                        continue;
                    }
                    long waitNs = head.deadlineNs - System.nanoTime();
                    if (waitNs <= 0L) {
                        queue.poll();
                        due = head.item;
                        break;
                    }
                    changed.await(waitNs, TimeUnit.NANOSECONDS);
                }
            } catch (InterruptedException e) {
                return;
            } finally {
                lock.unlock();
            }
            try {
                sink.release(due);
            } catch (RuntimeException e) {
                android.util.Log.w("DeadlinePacer", "Release failed", e);
            }
        }
    }
}
