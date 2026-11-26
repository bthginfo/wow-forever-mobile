package com.winlator.xserver

import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DeadlinePacerTest {
    private data class Release(val name: String, val atNs: Long)

    @Test
    fun releasesItemsInDeadlineOrderAndNotBeforeTheirDeadline() {
        val released = CopyOnWriteArrayList<Release>()
        val done = CountDownLatch(3)
        val pacer = DeadlinePacer<String>("test") {
            released += Release(it, System.nanoTime())
            done.countDown()
        }
        val start = System.nanoTime()
        pacer.schedule("late", start + ms(60))
        pacer.schedule("early", start + ms(20))
        pacer.schedule("middle", start + ms(40))
        try {
            assertTrue(done.await(2, TimeUnit.SECONDS))
            assertEquals(listOf("early", "middle", "late"), released.map { it.name })
            val deadlines = mapOf("early" to ms(20), "middle" to ms(40), "late" to ms(60))
            for (release in released) assertTrue(release.atNs - start >= deadlines.getValue(release.name))
        } finally {
            pacer.close()
        }
    }

    @Test
    fun anEarlierDeadlineWakesThePacerWhileItWaitsForALaterOne() {
        val released = CopyOnWriteArrayList<Release>()
        val first = CountDownLatch(1)
        val pacer = DeadlinePacer<String>("test") {
            released += Release(it, System.nanoTime())
            first.countDown()
        }
        val start = System.nanoTime()
        pacer.schedule("far", start + ms(1_500))
        Thread.sleep(30)
        pacer.schedule("soon", System.nanoTime() + ms(10))
        try {
            assertTrue(first.await(1, TimeUnit.SECONDS))
            assertEquals("soon", released.first().name)
            assertTrue(released.first().atNs - start < ms(700))
        } finally {
            pacer.close()
        }
    }

    @Test
    fun theThreadBlocksInsteadOfPollingWhenNothingIsDue() {
        val pacer = DeadlinePacer<String>("test") {}
        pacer.schedule("now", System.nanoTime())
        try {
            val thread = pacer.threadForTest()!!
            val deadline = System.nanoTime() + ms(1_000)
            while (pacer.pendingCount() > 0 || thread.state != Thread.State.WAITING) {
                assertTrue("pacer thread never went idle: ${thread.state}", System.nanoTime() < deadline)
                Thread.sleep(5)
            }
            // A polling loop would keep waking up into TIMED_WAITING or RUNNABLE.
            repeat(10) {
                Thread.sleep(3)
                assertEquals(Thread.State.WAITING, thread.state)
            }
        } finally {
            pacer.close()
        }
    }

    @Test
    fun matchingItemsAreReleasedImmediatelyAndOthersKeepTheirDeadline() {
        val released = CopyOnWriteArrayList<String>()
        val pacer = DeadlinePacer<String>("test") { released += it }
        val later = System.nanoTime() + ms(5_000)
        pacer.schedule("window-a-1", later)
        pacer.schedule("window-b-1", later)
        pacer.schedule("window-a-2", later + 1)
        try {
            pacer.releaseMatching { it.startsWith("window-a") }
            assertEquals(listOf("window-a-1", "window-a-2"), released)
            assertEquals(1, pacer.pendingCount())
        } finally {
            pacer.close()
        }
    }

    @Test
    fun closingStopsTheThreadAndIgnoresLaterItems() {
        val released = CopyOnWriteArrayList<String>()
        val pacer = DeadlinePacer<String>("test") { released += it }
        pacer.schedule("pending", System.nanoTime() + ms(5_000))
        val thread = pacer.threadForTest()!!
        pacer.close()
        thread.join(1_000)
        assertEquals(Thread.State.TERMINATED, thread.state)
        pacer.schedule("after close", System.nanoTime())
        assertEquals(emptyList<String>(), released)
        assertEquals(0, pacer.pendingCount())
    }

    private fun ms(value: Long) = TimeUnit.MILLISECONDS.toNanos(value)
}
