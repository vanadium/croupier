// Copyright 2015 The Vanadium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// util.go stores constants relevant to the syncbase hierarchy

package sync

const (
	// switch back to my mountpoint with the following code:
	//MountPoint = "users/emshack@google.com"
	MountPoint        = "/192.168.86.254:8101"
	UserID            = 2222
	UserColor         = 16777215
	UserAvatar        = "man.png"
	UserName          = "Bob"
	SBName            = "syncbase1"
	AppName           = "app"
	DbName            = "db"
	LogName           = "games"
	SettingsName      = "table_settings"
	CroupierInterface = "CroupierSettingsAndGame"
)
