package common

import "sync"

var GlobalCache *Cache

type Cache struct {
	MatchCache sync.Map
}

func NewCache() *Cache {
	c := new(Cache)
	return c
}

func (c *Cache) LoadEntry(id string) (interface{}, error) {
	bucket := &c.MatchCache
	val, _ := bucket.Load(id)
	return val, nil
}

func (c *Cache) SaveEntry(id string, entry interface{}) error {
	bucket := &c.MatchCache
	bucket.Store(id, entry)
	return nil
}

func (c *Cache) DeleteEntry(id string) error {
	bucket := &c.MatchCache
	bucket.Delete(id)
	return nil
}

func init() {
	GlobalCache = NewCache()
}
