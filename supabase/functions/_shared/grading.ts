/**
 * Bet Grading Helper Functions
 *
 * Provides automatic grading logic for different market types:
 * - Moneyline: bet on the game winner
 * - Spread: bet on a team to cover the point spread
 * - Total: bet on over/under combined score
 */

// GradeResult matches Swift GradeResult enum: win, loss, push
export type GradeResult = 'win' | 'loss' | 'push';

export interface BetInfo {
  id: string;
  market: string; // market type: 'moneyline', 'spread', 'total'
  side: string;   // the side the bettor picked (e.g., "Lakers", "Lakers -3.5", "Over 220.5")
}

export interface EventScores {
  homeScore: number;
  awayScore: number;
  homeTeam: string;
  awayTeam: string;
}

export interface GradeOutcome {
  result: GradeResult;
  gradeDetails: string; // Human-readable explanation
}

/**
 * Extracts a numeric value from a string using regex.
 * Handles formats like "-3.5", "+7", "220.5", etc.
 * Returns null if no number found.
 */
function extractNumericValue(str: string): number | null {
  // Match optional sign followed by number (integer or decimal)
  const match = str.match(/-?\d+\.?\d*/);
  if (match) {
    const value = parseFloat(match[0]);
    if (!isNaN(value)) {
      return value;
    }
  }
  return null;
}

/**
 * Determines if a side string indicates the home team.
 * The side can be just the team name or include spread/point info.
 */
function isHomeTeamSide(side: string, homeTeam: string, awayTeam: string): boolean {
  // Normalize for comparison (lowercase, trim)
  const normalizedSide = side.toLowerCase().trim();
  const normalizedHome = homeTeam.toLowerCase().trim();
  const normalizedAway = awayTeam.toLowerCase().trim();

  // Check if side starts with or contains the home team name
  // This handles cases like "Lakers" or "Lakers -3.5"
  if (normalizedSide.startsWith(normalizedHome) || normalizedSide.includes(normalizedHome)) {
    return true;
  }

  // If it contains away team, it's not home
  if (normalizedSide.startsWith(normalizedAway) || normalizedSide.includes(normalizedAway)) {
    return false;
  }

  // Default to false if we can't determine
  return false;
}

/**
 * Grades a moneyline bet.
 * Moneyline is simply picking the game winner.
 *
 * Rules:
 * - If bettor's team scored more points → won
 * - If bettor's team scored fewer points → lost
 * - If scores are tied → push (stake returned)
 */
export function gradeMoneylineBet(bet: BetInfo, scores: EventScores): GradeOutcome {
  const { homeScore, awayScore, homeTeam, awayTeam } = scores;

  // Determine which team the bettor picked
  const bettorPickedHome = isHomeTeamSide(bet.side, homeTeam, awayTeam);
  const bettorTeam = bettorPickedHome ? homeTeam : awayTeam;
  const bettorScore = bettorPickedHome ? homeScore : awayScore;
  const opponentScore = bettorPickedHome ? awayScore : homeScore;

  const finalScoreStr = `Final: ${awayScore}-${homeScore}`;

  if (bettorScore > opponentScore) {
    return {
      result: 'win',
      gradeDetails: `Moneyline: ${bettorTeam} won. ${finalScoreStr}`,
    };
  } else if (bettorScore < opponentScore) {
    return {
      result: 'loss',
      gradeDetails: `Moneyline: ${bettorTeam} lost. ${finalScoreStr}`,
    };
  } else {
    // Tie game - push
    return {
      result: 'push',
      gradeDetails: `Moneyline: Game tied. ${finalScoreStr}`,
    };
  }
}

/**
 * Grades a spread bet.
 * The bettor wins if their team's adjusted score (score + spread) beats the opponent.
 *
 * Example: "Lakers -3.5" means Lakers need to win by more than 3.5 points.
 *   - Lakers 105, Opponent 100: 105 + (-3.5) = 101.5 > 100 → won
 *   - Lakers 103, Opponent 100: 103 + (-3.5) = 99.5 < 100 → lost
 *
 * Example: "Celtics +7" means Celtics can lose by up to 6.5 and still win the bet.
 *   - Celtics 95, Opponent 100: 95 + 7 = 102 > 100 → won
 *   - Celtics 90, Opponent 100: 90 + 7 = 97 < 100 → lost
 */
export function gradeSpreadBet(bet: BetInfo, scores: EventScores): GradeOutcome {
  const { homeScore, awayScore, homeTeam, awayTeam } = scores;

  // Extract the spread value from the side string
  const spread = extractNumericValue(bet.side);
  if (spread === null) {
    return {
      result: 'push',
      gradeDetails: `Spread: Could not parse spread from "${bet.side}". Treating as push.`,
    };
  }

  // Determine which team the bettor picked
  const bettorPickedHome = isHomeTeamSide(bet.side, homeTeam, awayTeam);
  const bettorTeam = bettorPickedHome ? homeTeam : awayTeam;
  const bettorScore = bettorPickedHome ? homeScore : awayScore;
  const opponentScore = bettorPickedHome ? awayScore : homeScore;

  // Calculate adjusted score
  const adjustedScore = bettorScore + spread;
  const finalScoreStr = `Final: ${awayScore}-${homeScore}`;
  const spreadStr = spread >= 0 ? `+${spread}` : `${spread}`;

  if (adjustedScore > opponentScore) {
    return {
      result: 'win',
      gradeDetails: `Spread: ${bettorTeam} ${spreadStr} covered (${bettorScore}${spreadStr}=${adjustedScore} > ${opponentScore}). ${finalScoreStr}`,
    };
  } else if (adjustedScore < opponentScore) {
    return {
      result: 'loss',
      gradeDetails: `Spread: ${bettorTeam} ${spreadStr} did not cover (${bettorScore}${spreadStr}=${adjustedScore} < ${opponentScore}). ${finalScoreStr}`,
    };
  } else {
    // Exactly equal - push
    return {
      result: 'push',
      gradeDetails: `Spread: ${bettorTeam} ${spreadStr} pushed (${bettorScore}${spreadStr}=${adjustedScore} = ${opponentScore}). ${finalScoreStr}`,
    };
  }
}

/**
 * Grades a total (over/under) bet.
 * The bettor picks whether the combined score will be over or under a specified total.
 *
 * Example: "Over 220.5" - combined score needs to be 221+ to win
 * Example: "Under 220.5" - combined score needs to be 220 or less to win
 */
export function gradeTotalBet(bet: BetInfo, scores: EventScores): GradeOutcome {
  const { homeScore, awayScore } = scores;

  // Extract the total value from the side string
  const total = extractNumericValue(bet.side);
  if (total === null) {
    return {
      result: 'push',
      gradeDetails: `Total: Could not parse total from "${bet.side}". Treating as push.`,
    };
  }

  // Determine if it's an over or under bet
  const normalizedSide = bet.side.toLowerCase();
  const isOver = normalizedSide.includes('over');
  const isUnder = normalizedSide.includes('under');

  if (!isOver && !isUnder) {
    return {
      result: 'push',
      gradeDetails: `Total: Could not determine over/under from "${bet.side}". Treating as push.`,
    };
  }

  const combinedScore = homeScore + awayScore;
  const finalScoreStr = `Final: ${awayScore}-${homeScore} (Total: ${combinedScore})`;

  if (combinedScore > total) {
    // Over wins, under loses
    if (isOver) {
      return {
        result: 'win',
        gradeDetails: `Total: Over ${total} hit (${combinedScore} > ${total}). ${finalScoreStr}`,
      };
    } else {
      return {
        result: 'loss',
        gradeDetails: `Total: Under ${total} missed (${combinedScore} > ${total}). ${finalScoreStr}`,
      };
    }
  } else if (combinedScore < total) {
    // Under wins, over loses
    if (isUnder) {
      return {
        result: 'win',
        gradeDetails: `Total: Under ${total} hit (${combinedScore} < ${total}). ${finalScoreStr}`,
      };
    } else {
      return {
        result: 'loss',
        gradeDetails: `Total: Over ${total} missed (${combinedScore} < ${total}). ${finalScoreStr}`,
      };
    }
  } else {
    // Exactly equal - push
    return {
      result: 'push',
      gradeDetails: `Total: Pushed at ${total} (${combinedScore} = ${total}). ${finalScoreStr}`,
    };
  }
}

/**
 * Grades a team total bet.
 * The bettor picks whether an individual team's score will be over or under a specified total.
 *
 * Example: "Lakers Over 110.5" - Lakers need to score 111+ to win
 * Example: "Celtics Under 108.5" - Celtics need to score 108 or less to win
 */
export function gradeTeamTotalBet(bet: BetInfo, scores: EventScores): GradeOutcome {
  const { homeScore, awayScore, homeTeam, awayTeam } = scores;

  // Extract the total value from the side string
  const total = extractNumericValue(bet.side);
  if (total === null) {
    return {
      result: 'push',
      gradeDetails: `Team Total: Could not parse total from "${bet.side}". Treating as push.`,
    };
  }

  // Determine if it's an over or under bet
  const normalizedSide = bet.side.toLowerCase();
  const isOver = normalizedSide.includes('over');
  const isUnder = normalizedSide.includes('under');

  if (!isOver && !isUnder) {
    return {
      result: 'push',
      gradeDetails: `Team Total: Could not determine over/under from "${bet.side}". Treating as push.`,
    };
  }

  // Determine which team this bet is for
  const bettorPickedHome = isHomeTeamSide(bet.side, homeTeam, awayTeam);
  const teamName = bettorPickedHome ? homeTeam : awayTeam;
  const teamScore = bettorPickedHome ? homeScore : awayScore;
  const finalScoreStr = `Final: ${awayScore}-${homeScore} (${teamName}: ${teamScore})`;

  if (teamScore > total) {
    if (isOver) {
      return {
        result: 'win',
        gradeDetails: `Team Total: ${teamName} Over ${total} hit (${teamScore} > ${total}). ${finalScoreStr}`,
      };
    } else {
      return {
        result: 'loss',
        gradeDetails: `Team Total: ${teamName} Under ${total} missed (${teamScore} > ${total}). ${finalScoreStr}`,
      };
    }
  } else if (teamScore < total) {
    if (isUnder) {
      return {
        result: 'win',
        gradeDetails: `Team Total: ${teamName} Under ${total} hit (${teamScore} < ${total}). ${finalScoreStr}`,
      };
    } else {
      return {
        result: 'loss',
        gradeDetails: `Team Total: ${teamName} Over ${total} missed (${teamScore} < ${total}). ${finalScoreStr}`,
      };
    }
  } else {
    return {
      result: 'push',
      gradeDetails: `Team Total: ${teamName} pushed at ${total} (${teamScore} = ${total}). ${finalScoreStr}`,
    };
  }
}

/**
 * Main grading function that dispatches to the appropriate grading logic
 * based on market type.
 *
 * @param bet - The bet information including market type and side
 * @param scores - The final scores of the event
 * @returns The grade result and explanation
 */
export function gradeBet(bet: BetInfo, scores: EventScores): GradeOutcome {
  const marketType = bet.market.toLowerCase();

  switch (marketType) {
    case 'moneyline':
    case 'h2h':
      return gradeMoneylineBet(bet, scores);

    case 'spread':
    case 'spreads':
    case 'alternate_spread':
      return gradeSpreadBet(bet, scores);

    case 'total':
    case 'totals':
    case 'over_under':
    case 'alternate_total':
      return gradeTotalBet(bet, scores);

    case 'team_total':
      return gradeTeamTotalBet(bet, scores);

    case 'outright':
      return {
        result: 'push',
        gradeDetails: 'Outright/futures market: manual grading required.',
      };

    default:
      // Unknown market type - cannot grade automatically
      return {
        result: 'push',
        gradeDetails: `Unknown market type "${bet.market}". Manual grading required.`,
      };
  }
}
