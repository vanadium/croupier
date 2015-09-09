package table

import (
	"math/rand"
	"sprites/card"
	"sprites/player"
)

func NewTable(p []*player.Player) *Table {
	return &Table{
		players:     p,
		trick:       []*card.Card{nil, nil, nil, nil},
		firstPlayed: -1,
		allCards:    nil,
	}
}

type Table struct {
	//players and trick should each have 4 elements
	players []*player.Player
	trick   []*card.Card
	//firstPlayed is the index in trick of the card played first
	firstPlayed int
	allCards    []*card.Card
}

func (t *Table) GetPlayers() []*player.Player {
	return t.players
}

func (t *Table) SetFirst(index int) {
	t.firstPlayed = index
}

func (t *Table) GenerateCards() {
	t.allCards = make([]*card.Card, 0)
	for i := 0; i < 13; i++ {
		t.allCards = append(t.allCards, card.NewCard(i+2, "C"))
		t.allCards = append(t.allCards, card.NewCard(i+2, "D"))
		t.allCards = append(t.allCards, card.NewCard(i+2, "S"))
		t.allCards = append(t.allCards, card.NewCard(i+2, "H"))
	}
}

func (t *Table) PlayCard(c *card.Card, playerIndex int) {
	t.trick[playerIndex] = c
}

func (t *Table) SendTrick() {
	trickSuit := t.trick[t.firstPlayed].GetSuit()
	highest := -1
	highestIndex := -1
	for i := 0; i < 4; i++ {
		curCard := t.trick[i]
		if curCard.GetSuit() == trickSuit && curCard.GetNum() > highest {
			highest = curCard.GetNum()
			highestIndex = i
		}
	}
	//clear trick
	t.players[highestIndex].TakeTrick(t.trick)
	for i := 0; i < 4; i++ {
		t.trick[i] = nil
	}
}

func (t *Table) ScoreRound() {
	roundScores := []int{0, 0, 0, 0}
	shotMoon := false
	shooter := -1
	for i := 0; i < 4; i++ {
		roundScores[i] = t.players[i].CalculateScore()
		if roundScores[i] == 26 {
			shotMoon = true
			shooter = i
		}
	}
	//if the moon was shot
	if shotMoon == true {
		for i := 0; i < 4; i++ {
			if i == shooter {
				roundScores[i] = 0
			} else {
				roundScores[i] = 26
			}
		}
	}
	//sending scores to players
	for i := 0; i < 4; i++ {
		t.players[i].UpdateScore(roundScores[i])
	}
}

func (t *Table) Deal() {
	if t.allCards == nil {
		t.GenerateCards()
	}
	shuffle := rand.Perm(52)
	for i := 0; i < 4; i++ {
		hand := make([]*card.Card, 0)
		for j := 0; j < 13; j++ {
			hand = append(hand, t.allCards[shuffle[j+13*i]])
		}
		t.players[i].SetHand(hand)
	}
}