CREATE TABLE IF NOT EXISTS `pmms_playlists` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `owner_license` varchar(64) NOT NULL,
  `name` varchar(255) NOT NULL,
  `is_favorite` tinyint(1) NOT NULL DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `pmms_playlist_tracks` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `playlist_id` int(11) NOT NULL,
  `title` varchar(255) NOT NULL,
  `url` text NOT NULL,
  `duration` int(11) DEFAULT NULL,
  `added_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  FOREIGN KEY (`playlist_id`) REFERENCES `pmms_playlists`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `pmms_friends` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `user_license` varchar(64) NOT NULL,
  `friend_license` varchar(64) NOT NULL, 
  `friend_name` varchar(255) DEFAULT NULL,
  `status` enum('pending','accepted') NOT NULL DEFAULT 'pending',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_friendship` (`user_license`, `friend_license`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `pmms_known_players` (
  `license` varchar(64) NOT NULL,
  `display_name` varchar(255) DEFAULT NULL,
  `last_seen_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `last_menu_opened_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`license`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `pmms_shared_playlists` (
  `playlist_id` int(11) NOT NULL,
  `shared_with_license` varchar(64) NOT NULL,
  PRIMARY KEY (`playlist_id`, `shared_with_license`),
  FOREIGN KEY (`playlist_id`) REFERENCES `pmms_playlists`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
