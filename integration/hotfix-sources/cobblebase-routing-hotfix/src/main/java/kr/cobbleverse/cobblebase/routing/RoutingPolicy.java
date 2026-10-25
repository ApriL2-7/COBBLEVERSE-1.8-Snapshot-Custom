package kr.cobbleverse.cobblebase.routing;

import java.util.Comparator;
import java.util.List;
import java.util.Objects;
import java.util.Optional;
import java.util.function.Predicate;

public final class RoutingPolicy {
    // An existing stack may beat a chest that is at most two blocks closer.
    private static final double EXACT_STACK_BONUS_BLOCKS = 2.0;
    // Capacity only breaks close calls; it must never send a gatherer across the storage room.
    private static final double MAX_CAPACITY_BONUS_BLOCKS = 0.5;

    private RoutingPolicy() {
    }

    public interface Candidate {
        String category();
        boolean hasExactStack();
        int capacity();
        boolean completelyEmpty();
        double distanceSquared();
    }

    public static <T extends Candidate> Optional<T> select(
        List<T> candidates,
        String matchingCategory,
        String fallbackCategory,
        Predicate<T> accessible
    ) {
        if (matchingCategory != null) {
            Optional<T> categoryMatch = best(candidates, candidate ->
                Objects.equals(candidate.category(), matchingCategory) && accessible.test(candidate));
            if (categoryMatch.isPresent()) {
                return categoryMatch;
            }
        }

        Optional<T> uncategorizedExact = best(candidates, candidate ->
            candidate.category() == null && candidate.hasExactStack() && accessible.test(candidate));
        if (uncategorizedExact.isPresent()) {
            return uncategorizedExact;
        }

        Optional<T> fallback = best(candidates, candidate ->
            Objects.equals(candidate.category(), fallbackCategory) && accessible.test(candidate));
        if (fallback.isPresent()) {
            return fallback;
        }

        return best(candidates, candidate ->
            candidate.category() == null && candidate.completelyEmpty() && accessible.test(candidate));
    }

    private static <T extends Candidate> Optional<T> best(List<T> candidates, Predicate<T> filter) {
        return candidates.stream()
            .filter(filter)
            .min(Comparator
                .comparingDouble(RoutingPolicy::adjustedDistance)
                .thenComparingDouble(Candidate::distanceSquared)
                .thenComparing(Comparator.comparingInt(Candidate::capacity).reversed()));
    }

    private static double adjustedDistance(Candidate candidate) {
        double distance = Math.sqrt(Math.max(0.0, candidate.distanceSquared()));
        double exactBonus = candidate.hasExactStack() ? EXACT_STACK_BONUS_BLOCKS : 0.0;
        double capacityRatio = Math.min(Math.max(candidate.capacity(), 0), 64) / 64.0;
        return distance - exactBonus - capacityRatio * MAX_CAPACITY_BONUS_BLOCKS;
    }
}
