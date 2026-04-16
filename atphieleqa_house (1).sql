-- phpMyAdmin SQL Dump
-- version 5.2.2
-- https://www.phpmyadmin.net/
--
-- Host: localhost:3306
-- Generation Time: Mar 23, 2026 at 12:56 PM
-- Server version: 11.4.10-MariaDB-cll-lve
-- PHP Version: 8.3.30

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `atphieleqa_house`
--

-- --------------------------------------------------------

--
-- Table structure for table `activity_logs`
--

CREATE TABLE `activity_logs` (
  `id` int(11) NOT NULL,
  `user_id` int(11) DEFAULT NULL,
  `user_role` varchar(50) DEFAULT NULL,
  `action` varchar(255) NOT NULL,
  `description` text DEFAULT NULL,
  `ip_address` varchar(45) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

--
-- Dumping data for table `activity_logs`
--

INSERT INTO `activity_logs` (`id`, `user_id`, `user_role`, `action`, `description`, `ip_address`, `created_at`) VALUES
(1, 4, 'dealer', 'login', 'User logged in successfully', '165.56.186.225', '2026-03-01 14:07:52'),
(2, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.225', '2026-03-01 14:08:00'),
(3, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.225', '2026-03-01 14:08:24'),
(4, NULL, 'dealer', 'register', 'New user registered: chisalaluckykk5@gmail.com (dealer)', '165.56.186.225', '2026-03-01 14:09:51'),
(5, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.47', '2026-03-01 14:12:19'),
(6, 2, 'admin', 'delete_user', 'Deleted user ID: 46', '165.56.186.47', '2026-03-01 14:12:33'),
(7, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.30', '2026-03-01 14:18:57'),
(8, 4, 'dealer', 'login', 'User logged in successfully', '45.215.224.192', '2026-03-01 14:56:08'),
(9, 2, 'admin', 'login', 'User logged in successfully', '45.215.224.192', '2026-03-01 14:57:19'),
(10, 2, 'admin', 'login', 'User logged in successfully', '45.215.224.192', '2026-03-01 15:21:46'),
(11, 4, 'dealer', 'login', 'User logged in successfully', '165.58.129.42', '2026-03-01 17:56:33'),
(12, 2, 'admin', 'login', 'User logged in successfully', '45.215.255.229', '2026-03-01 18:13:12'),
(13, 2, 'admin', 'login', 'User logged in successfully', '45.215.255.229', '2026-03-01 18:28:26'),
(14, 2, 'admin', 'login', 'User logged in successfully', '45.215.255.229', '2026-03-01 19:07:37'),
(15, 2, 'admin', 'login', 'User logged in successfully', '45.215.255.229', '2026-03-01 20:05:13'),
(16, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.101', '2026-03-01 20:15:25'),
(17, 2, 'admin', 'login', 'User logged in successfully', '45.215.255.71', '2026-03-02 04:56:00'),
(18, 2, 'admin', 'login', 'User logged in successfully', '45.215.249.19', '2026-03-02 06:42:19'),
(19, 2, 'admin', 'login', 'User logged in successfully', '165.56.183.227', '2026-03-02 07:15:42'),
(20, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.78', '2026-03-02 08:36:07'),
(21, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.232', '2026-03-02 10:31:41'),
(22, 47, 'user', 'register', 'New user registered: frank.t.r.b59@gmail.com (user)', '51.77.74.105', '2026-03-02 11:46:37'),
(23, 47, 'user', 'login', 'User logged in successfully', '51.77.74.105', '2026-03-02 11:47:35'),
(24, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.97', '2026-03-02 12:18:24'),
(25, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.243', '2026-03-02 14:42:10'),
(26, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.192', '2026-03-02 15:12:17'),
(27, 4, 'dealer', 'login', 'User logged in successfully', '165.58.129.192', '2026-03-02 15:41:09'),
(28, 4, 'dealer', 'login', 'User logged in successfully', '165.58.129.192', '2026-03-02 15:42:01'),
(29, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.192', '2026-03-02 16:24:58'),
(30, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.192', '2026-03-02 16:51:11'),
(31, 2, 'admin', 'login', 'User logged in successfully', '165.56.183.236', '2026-03-02 20:21:56'),
(32, 4, 'dealer', 'login', 'User logged in successfully', '165.56.186.144', '2026-03-02 20:58:38'),
(33, 2, 'admin', 'login', 'User logged in successfully', '165.56.183.233', '2026-03-02 21:06:16'),
(34, 4, 'dealer', 'login', 'User logged in successfully', '165.58.129.59', '2026-03-02 22:11:48'),
(35, 4, 'dealer', 'login', 'User logged in successfully', '165.58.129.79', '2026-03-02 22:48:22'),
(36, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.227', '2026-03-02 23:02:33'),
(37, 4, 'dealer', 'login', 'User logged in successfully', '165.58.129.227', '2026-03-02 23:05:38'),
(38, 4, 'dealer', 'login', 'User logged in successfully', '165.58.129.23', '2026-03-02 23:26:27'),
(39, 4, 'dealer', 'login', 'User logged in successfully', '165.58.129.23', '2026-03-02 23:44:38'),
(40, 49, 'dealer', 'register', 'New user registered: deleyi5268@ostahie.com (dealer)', '104.28.46.100', '2026-03-03 04:23:23'),
(41, 49, 'dealer', 'login', 'User logged in successfully', '104.28.46.100', '2026-03-03 04:24:13'),
(42, 2, 'admin', 'login', 'User logged in successfully', '165.56.183.146', '2026-03-03 06:05:59'),
(43, 2, 'admin', 'login', 'User logged in successfully', '165.56.183.146', '2026-03-03 06:07:16'),
(44, 4, 'dealer', 'login', 'User logged in successfully', '165.56.183.146', '2026-03-03 06:13:17'),
(45, 2, 'admin', 'login', 'User logged in successfully', '165.56.183.146', '2026-03-03 06:39:47'),
(46, 4, 'dealer', 'login', 'User logged in successfully', '165.56.183.146', '2026-03-03 06:41:51'),
(47, 2, 'admin', 'login', 'User logged in successfully', '165.56.183.146', '2026-03-03 06:46:56'),
(48, 2, 'admin', 'login', 'User logged in successfully', '165.56.183.146', '2026-03-03 06:54:27'),
(49, 2, 'admin', 'ban_user', 'Changed ban status for user ID: 49 to 1', '165.56.183.146', '2026-03-03 06:55:45'),
(50, 2, 'admin', 'unban_user', 'Changed ban status for user ID: 49 to 0', '165.56.183.146', '2026-03-03 06:56:06'),
(51, 2, 'admin', 'login', 'User logged in successfully', '165.56.183.79', '2026-03-03 08:50:22'),
(52, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.141', '2026-03-03 14:48:28'),
(53, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.112', '2026-03-03 17:40:36'),
(54, 2, 'admin', 'login', 'User logged in successfully', '165.56.183.51', '2026-03-03 18:46:00'),
(55, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.181', '2026-03-03 20:21:48'),
(56, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.125', '2026-03-04 04:37:08'),
(57, 4, 'dealer', 'login', 'User logged in successfully', '165.58.129.191', '2026-03-04 06:44:38'),
(58, 4, 'dealer', 'login', 'User logged in successfully', '165.58.129.191', '2026-03-04 06:47:17'),
(59, 2, 'admin', 'login', 'User logged in successfully', '165.56.183.45', '2026-03-04 10:31:31'),
(60, 2, 'admin', 'login', 'User logged in successfully', '102.208.220.203', '2026-03-04 15:19:29'),
(61, 2, 'admin', 'login', 'User logged in successfully', '102.208.220.203', '2026-03-04 19:27:22'),
(62, 4, 'dealer', 'login', 'User logged in successfully', '165.58.129.9', '2026-03-04 20:40:54'),
(63, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.9', '2026-03-04 20:42:37'),
(64, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.186', '2026-03-04 21:09:11'),
(65, 4, 'dealer', 'login', 'User logged in successfully', '165.56.186.109', '2026-03-04 21:47:49'),
(66, 4, 'dealer', 'login', 'User logged in successfully', '165.56.186.109', '2026-03-04 22:12:41'),
(67, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.109', '2026-03-04 22:15:24'),
(68, 4, 'dealer', 'login', 'User logged in successfully', '165.56.186.109', '2026-03-04 22:36:40'),
(69, 4, 'dealer', 'login', 'User logged in successfully', '165.56.186.109', '2026-03-04 23:01:58'),
(70, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.109', '2026-03-04 23:06:49'),
(71, 4, 'dealer', 'login', 'User logged in successfully', '165.56.186.109', '2026-03-04 23:10:20'),
(72, 4, 'dealer', 'login', 'User logged in successfully', '165.56.186.109', '2026-03-04 23:11:48'),
(73, 4, 'dealer', 'login', 'User logged in successfully', '165.56.186.109', '2026-03-04 23:20:43'),
(74, 4, 'dealer', 'login', 'User logged in successfully', '165.56.186.109', '2026-03-04 23:23:36'),
(75, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.148', '2026-03-05 05:12:00'),
(76, 2, 'admin', 'login', 'User logged in successfully', '102.208.220.203', '2026-03-05 12:04:26'),
(77, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.53', '2026-03-05 15:30:09'),
(78, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.53', '2026-03-05 16:17:46'),
(79, 4, 'dealer', 'login', 'User logged in successfully', '165.56.186.53', '2026-03-05 16:27:40'),
(80, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.53', '2026-03-05 16:29:36'),
(81, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.53', '2026-03-05 16:38:13'),
(82, 50, 'dealer', 'register', 'New user registered: dannynkhata6@gmail.com (dealer)', '45.215.237.154', '2026-03-05 16:41:52'),
(83, 50, 'dealer', 'login', 'User logged in successfully', '45.215.237.154', '2026-03-05 16:42:58'),
(84, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.53', '2026-03-05 16:52:52'),
(85, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.53', '2026-03-05 16:58:48'),
(86, 4, 'dealer', 'login', 'User logged in successfully', '165.56.186.53', '2026-03-05 17:03:28'),
(87, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.53', '2026-03-05 17:15:30'),
(88, 4, 'dealer', 'login', 'User logged in successfully', '165.56.186.53', '2026-03-05 17:20:12'),
(89, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.53', '2026-03-05 17:38:14'),
(90, 4, 'dealer', 'login', 'User logged in successfully', '165.56.186.53', '2026-03-05 17:57:11'),
(91, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.53', '2026-03-05 18:12:10'),
(92, 4, 'dealer', 'login', 'User logged in successfully', '165.56.186.53', '2026-03-05 18:15:41'),
(93, 2, 'admin', 'login', 'User logged in successfully', '45.215.255.122', '2026-03-05 20:17:57'),
(94, 2, 'admin', 'login', 'User logged in successfully', '45.215.255.122', '2026-03-05 20:31:15'),
(95, NULL, 'user', 'register', 'New user registered: chisalavudo@gmail.com (user)', '165.57.81.152', '2026-03-05 20:37:32'),
(96, NULL, 'user', 'login', 'User logged in successfully', '165.57.81.152', '2026-03-05 20:38:27'),
(97, 2, 'admin', 'login', 'User logged in successfully', '165.57.81.152', '2026-03-05 20:38:44'),
(98, 2, 'admin', 'delete_user', 'Deleted user ID: 55', '165.57.81.152', '2026-03-05 20:39:08'),
(99, NULL, 'user', 'register', 'New user registered: chisalavudo@gmail.com (user)', '165.57.81.152', '2026-03-05 20:40:18'),
(100, NULL, 'user', 'login', 'User logged in successfully', '165.57.81.152', '2026-03-05 20:40:56'),
(101, 2, 'admin', 'login', 'User logged in successfully', '165.57.81.152', '2026-03-05 20:41:10'),
(102, 2, 'admin', 'delete_user', 'Deleted user ID: 56', '165.57.81.152', '2026-03-05 20:41:27'),
(103, NULL, 'dealer', 'register', 'New user registered: chisalavudo@gmail.com (dealer)', '165.57.81.152', '2026-03-05 20:42:01'),
(104, NULL, 'dealer', 'login', 'User logged in successfully', '165.57.81.152', '2026-03-05 20:42:21'),
(105, 2, 'admin', 'login', 'User logged in successfully', '45.215.255.122', '2026-03-05 21:07:01'),
(106, 2, 'admin', 'delete_user', 'Deleted user ID: 58', '165.57.81.29', '2026-03-05 21:25:49'),
(107, NULL, 'dealer', 'login', 'User logged in successfully', '165.57.81.29', '2026-03-05 21:27:22'),
(108, 2, 'admin', 'login', 'User logged in successfully', '165.57.81.29', '2026-03-05 21:28:21'),
(109, 4, 'dealer', 'login', 'User logged in successfully', '165.57.81.29', '2026-03-05 21:30:36'),
(110, 2, 'admin', 'login', 'User logged in successfully', '45.215.249.43', '2026-03-06 07:31:51'),
(111, 4, 'dealer', 'login', 'User logged in successfully', '45.215.249.43', '2026-03-06 07:46:04'),
(112, NULL, 'dealer', 'login', 'User logged in successfully', '45.215.249.43', '2026-03-06 07:48:43'),
(113, 4, 'dealer', 'login', 'User logged in successfully', '45.215.236.73', '2026-03-06 09:31:45'),
(114, 4, 'dealer', 'login', 'User logged in successfully', '45.215.236.73', '2026-03-06 09:49:08'),
(115, 63, 'dealer', 'register', 'New user registered: gggeraldshamulanga@gmail.com (dealer)', '102.147.237.46', '2026-03-06 10:11:54'),
(116, 63, 'dealer', 'login', 'User logged in successfully', '102.147.237.46', '2026-03-06 10:12:33'),
(117, 63, 'dealer', 'login', 'User logged in successfully', '102.147.237.46', '2026-03-06 10:15:02'),
(118, 63, 'dealer', 'login', 'User logged in successfully', '41.216.95.230', '2026-03-06 10:16:05'),
(119, 63, 'dealer', 'login', 'User logged in successfully', '41.216.95.230', '2026-03-06 10:17:38'),
(120, 63, 'dealer', 'login', 'User logged in successfully', '41.216.95.230', '2026-03-06 10:17:38'),
(121, 2, 'admin', 'login', 'User logged in successfully', '45.215.236.73', '2026-03-06 10:21:08'),
(122, 63, 'dealer', 'login', 'User logged in successfully', '41.216.95.230', '2026-03-06 10:33:02'),
(123, NULL, 'dealer', 'register', 'New user registered: chisalavudo@gmail.com (dealer)', '45.215.236.73', '2026-03-06 10:33:04'),
(124, NULL, 'dealer', 'login', 'User logged in successfully', '45.215.236.73', '2026-03-06 10:33:22'),
(125, NULL, 'dealer', 'login', 'User logged in successfully', '45.215.236.73', '2026-03-06 10:39:35'),
(126, 2, 'admin', 'login', 'User logged in successfully', '45.215.236.73', '2026-03-06 10:45:31'),
(127, 2, 'admin', 'login', 'User logged in successfully', '45.215.236.73', '2026-03-06 12:03:35'),
(128, 2, 'admin', 'delete_user', 'Deleted user ID: 64', '45.215.236.73', '2026-03-06 12:03:59'),
(129, 2, 'admin', 'login', 'User logged in successfully', '45.215.236.73', '2026-03-06 13:09:51'),
(130, 4, 'dealer', 'login', 'User logged in successfully', '165.58.129.237', '2026-03-06 13:38:24'),
(131, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.237', '2026-03-06 13:41:56'),
(132, 4, 'dealer', 'login', 'User logged in successfully', '165.58.129.237', '2026-03-06 13:42:18'),
(133, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.237', '2026-03-06 13:43:20'),
(134, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.237', '2026-03-06 14:26:44'),
(135, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.237', '2026-03-06 15:05:27'),
(136, 4, 'dealer', 'login', 'User logged in successfully', '165.58.129.237', '2026-03-06 15:13:30'),
(137, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.237', '2026-03-06 16:26:47'),
(138, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.27', '2026-03-06 17:10:25'),
(139, 2, 'admin', 'login', 'User logged in successfully', '102.208.220.203', '2026-03-07 07:40:36'),
(140, 2, 'admin', 'login', 'User logged in successfully', '102.208.220.203', '2026-03-07 08:14:33'),
(141, 2, 'admin', 'update_subscription', 'Updated subscription for user ID: 63. Status: inactive, Expiry: 2026-04-05', '102.208.220.203', '2026-03-07 08:15:37'),
(142, 4, 'dealer', 'login', 'User logged in successfully', '102.208.220.203', '2026-03-07 08:26:15'),
(143, 2, 'admin', 'login', 'User logged in successfully', '102.208.220.203', '2026-03-07 12:00:15'),
(144, 2, 'admin', 'send_email', 'Sent email to user ID: 50. Subject: subscription', '102.208.220.203', '2026-03-07 12:24:03'),
(145, 2, 'admin', 'send_email', 'Sent email to user ID: 66. Subject: verification', '102.208.220.203', '2026-03-07 12:25:16'),
(146, 2, 'admin', 'send_email', 'Sent email to user ID: 37. Subject: verification', '102.208.220.203', '2026-03-07 12:25:36'),
(147, 2, 'admin', 'send_email', 'Sent email to user ID: 63. Subject: Happy customer', '102.208.220.203', '2026-03-07 12:30:11'),
(148, 2, 'admin', 'send_email', 'Sent email to user ID: 4. Subject: verification', '102.208.220.203', '2026-03-07 12:40:15'),
(149, 2, 'admin', 'login', 'User logged in successfully', '102.208.220.206', '2026-03-07 13:52:33'),
(150, 2, 'admin', 'login', 'User logged in successfully', '102.208.220.203', '2026-03-07 14:13:42'),
(151, 2, 'admin', 'login', 'User logged in successfully', '102.208.220.203', '2026-03-07 14:48:15'),
(152, 2, 'admin', 'login', 'User logged in successfully', '102.208.220.202', '2026-03-07 15:47:26'),
(153, 2, 'admin', 'login', 'User logged in successfully', '102.208.220.202', '2026-03-07 18:08:41'),
(154, 2, 'admin', 'login', 'User logged in successfully', '102.208.220.203', '2026-03-07 18:58:57'),
(155, 2, 'admin', 'login', 'User logged in successfully', '102.208.220.203', '2026-03-08 06:08:48'),
(156, 4, 'dealer', 'login', 'User logged in successfully', '102.208.220.203', '2026-03-08 08:40:33'),
(157, 4, 'dealer', 'login', 'User logged in successfully', '102.208.220.203', '2026-03-08 08:48:03'),
(158, 2, 'admin', 'login', 'User logged in successfully', '102.208.220.200', '2026-03-08 10:42:21'),
(159, 2, 'admin', 'login', 'User logged in successfully', '102.208.220.203', '2026-03-08 13:16:08'),
(160, 2, 'admin', 'login', 'User logged in successfully', '102.208.220.206', '2026-03-08 14:15:45'),
(161, 4, 'dealer', 'login', 'User logged in successfully', '102.208.220.206', '2026-03-08 14:16:08'),
(162, 2, 'admin', 'login', 'User logged in successfully', '102.208.220.202', '2026-03-08 16:25:24'),
(163, 2, 'admin', 'login', 'User logged in successfully', '102.208.220.203', '2026-03-08 17:17:27'),
(164, 2, 'admin', 'login', 'User logged in successfully', '102.208.220.203', '2026-03-08 19:12:33'),
(165, 2, 'admin', 'login', 'User logged in successfully', '102.208.220.203', '2026-03-08 19:12:37'),
(166, 2, 'admin', 'login', 'User logged in successfully', '102.208.220.203', '2026-03-09 06:47:10'),
(167, 2, 'admin', 'login', 'User logged in successfully', '102.208.220.203', '2026-03-09 06:47:32'),
(168, 2, 'admin', 'login', 'User logged in successfully', '102.208.220.203', '2026-03-09 10:46:18'),
(169, NULL, 'user', 'register', 'New user registered: josphatmp.86@gmail.com (user)', '41.60.174.186', '2026-03-09 12:19:04'),
(170, 2, 'admin', 'login', 'User logged in successfully', '102.208.220.203', '2026-03-09 14:16:12'),
(171, 2, 'admin', 'send_email', 'Sent email to user ID: 67. Subject: Welcome', '102.208.220.203', '2026-03-09 14:17:43'),
(172, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.103', '2026-03-09 19:51:31'),
(173, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.85', '2026-03-09 21:28:06'),
(174, 4, 'dealer', 'login', 'User logged in successfully', '165.58.129.85', '2026-03-09 21:28:22'),
(175, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.85', '2026-03-09 21:34:39'),
(176, 2, 'admin', 'delete_user', 'Deleted user ID: 65', '165.58.129.85', '2026-03-09 21:35:55'),
(177, NULL, 'user', 'register', 'New user registered: chisalavudo@gmail.com (user)', '165.58.129.85', '2026-03-09 21:36:35'),
(178, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.85', '2026-03-09 22:34:10'),
(179, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.85', '2026-03-09 22:44:58'),
(180, 2, 'admin', 'delete_user', 'Deleted user ID: 37', '165.58.129.85', '2026-03-09 22:46:03'),
(181, NULL, 'user', 'register', 'New user registered: chisalaluckson27@gmail.com (user)', '165.58.129.85', '2026-03-09 22:47:33'),
(182, 2, 'admin', 'delete_user', 'Deleted user ID: 37', '165.58.129.85', '2026-03-09 22:47:41'),
(183, 2, 'admin', 'delete_user', 'Deleted user ID: 37', '165.58.129.85', '2026-03-09 22:48:05'),
(184, 2, 'admin', 'delete_user', 'Deleted user ID: 68', '165.58.129.85', '2026-03-09 22:48:25'),
(185, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.87', '2026-03-10 04:39:33'),
(186, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.166', '2026-03-10 06:16:15'),
(187, NULL, 'dealer', 'register', 'New user registered: kambwanga2@gmail.com (dealer)', '165.58.129.161', '2026-03-10 07:44:26'),
(188, NULL, 'dealer', 'login', 'User logged in successfully', '165.58.129.161', '2026-03-10 07:46:45'),
(189, NULL, 'dealer', 'login', 'User logged in successfully', '165.58.129.161', '2026-03-10 07:49:28'),
(190, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.84', '2026-03-10 11:03:52'),
(191, 2, 'admin', 'send_email', 'Sent email to user ID: 70. Subject: Verification ', '165.58.129.84', '2026-03-10 11:06:31'),
(192, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.84', '2026-03-10 12:05:03'),
(193, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.84', '2026-03-10 12:08:19'),
(194, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.201', '2026-03-10 13:37:08'),
(195, 2, 'admin', 'ban_user', 'Changed ban status for user ID: 70 to 1', '165.56.186.201', '2026-03-10 13:39:07'),
(196, 2, 'admin', 'delete_user', 'Deleted user ID: 69', '165.56.186.201', '2026-03-10 13:40:44'),
(197, NULL, 'dealer', 'register', 'New user registered: chisalaluckson27@gmail.com (dealer)', '165.56.186.201', '2026-03-10 13:42:01'),
(198, 2, 'admin', 'delete_user', 'Deleted user ID: 69', '165.56.186.201', '2026-03-10 13:42:11'),
(199, NULL, 'dealer', 'login', 'User logged in successfully', '165.56.186.201', '2026-03-10 13:42:35'),
(200, 2, 'admin', 'delete_user', 'Deleted user ID: 69', '165.56.186.201', '2026-03-10 13:43:06'),
(201, 2, 'admin', 'delete_user', 'Deleted user ID: 71', '165.56.186.201', '2026-03-10 14:04:28'),
(202, NULL, 'dealer', 'register', 'New user registered: chisalaluckson27@gmail.com (dealer)', '165.56.186.201', '2026-03-10 14:07:11'),
(203, NULL, 'dealer', 'login', 'User logged in successfully', '165.56.186.201', '2026-03-10 14:07:45'),
(204, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.201', '2026-03-10 14:24:25'),
(205, NULL, 'dealer', 'login', 'User logged in successfully', '165.56.186.201', '2026-03-10 14:26:36'),
(206, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.201', '2026-03-10 14:27:40'),
(207, 2, 'admin', 'delete_user', 'Deleted user ID: 72', '165.56.186.201', '2026-03-10 14:27:54'),
(208, 2, 'admin', 'unban_user', 'Changed ban status for user ID: 70 to 0', '165.56.186.201', '2026-03-10 14:28:03'),
(209, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.201', '2026-03-10 14:29:28'),
(210, 2, 'admin', 'verify_user', 'Updated verification for user ID: 70 to 1', '165.56.186.201', '2026-03-10 14:31:04'),
(211, 2, 'admin', 'verify_user', 'Updated verification for user ID: 70 to 0', '165.56.186.201', '2026-03-10 14:31:08'),
(212, 2, 'admin', 'ban_user', 'Changed ban status for user ID: 70 to 1', '165.56.186.201', '2026-03-10 14:32:19'),
(213, 2, 'admin', 'delete_user', 'Deleted user ID: 70', '165.56.186.201', '2026-03-10 14:32:26'),
(214, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.201', '2026-03-10 15:30:01'),
(215, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.233', '2026-03-10 20:06:27'),
(216, 2, 'admin', 'login', 'User logged in successfully', '165.56.66.106', '2026-03-11 04:16:11'),
(217, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.244', '2026-03-11 07:52:58'),
(218, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.14', '2026-03-11 12:34:04'),
(219, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.97', '2026-03-11 14:04:51'),
(220, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.98', '2026-03-11 15:24:02'),
(221, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.98', '2026-03-11 15:27:02'),
(222, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.98', '2026-03-11 15:33:04'),
(223, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.98', '2026-03-11 16:25:48'),
(224, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.98', '2026-03-11 16:30:45'),
(225, 4, 'dealer', 'login', 'User logged in successfully', '165.56.186.98', '2026-03-11 16:46:34'),
(226, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.98', '2026-03-11 17:12:13'),
(227, 4, 'dealer', 'login', 'User logged in successfully', '165.56.186.98', '2026-03-11 17:14:17'),
(228, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.98', '2026-03-11 17:20:14'),
(229, 4, 'dealer', 'login', 'User logged in successfully', '165.56.186.98', '2026-03-11 17:24:58'),
(230, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.98', '2026-03-11 17:27:20'),
(231, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.98', '2026-03-11 18:12:21'),
(232, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.98', '2026-03-11 18:27:26'),
(233, 4, 'dealer', 'login', 'User logged in successfully', '165.56.186.98', '2026-03-11 18:27:54'),
(234, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.145', '2026-03-11 23:38:19'),
(235, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.145', '2026-03-12 04:55:25'),
(236, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.254', '2026-03-12 07:59:15'),
(237, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.70', '2026-03-12 09:09:33'),
(238, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.54', '2026-03-12 15:40:24'),
(239, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.98', '2026-03-12 17:59:23'),
(240, 2, 'admin', 'login', 'User logged in successfully', '165.57.81.47', '2026-03-12 19:40:43'),
(241, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.62', '2026-03-13 10:05:37'),
(242, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.63', '2026-03-13 12:39:41'),
(243, 4, 'dealer', 'login', 'User logged in successfully', '165.57.81.206', '2026-03-13 14:04:57'),
(244, 2, 'admin', 'login', 'User logged in successfully', '165.57.81.206', '2026-03-13 14:32:23'),
(245, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.18', '2026-03-13 15:52:11'),
(246, 2, 'admin', 'login', 'User logged in successfully', '102.208.220.203', '2026-03-13 20:06:02'),
(247, NULL, 'user', 'register', 'New user registered: aja.l.i.va.gosi5.36@gmail.com (user)', '185.129.62.62', '2026-03-14 02:44:31'),
(248, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.85', '2026-03-14 05:04:45'),
(249, 2, 'admin', 'ban_user', 'Changed ban status for user ID: 73 to 1', '165.56.186.85', '2026-03-14 05:05:23'),
(250, 2, 'admin', 'delete_user', 'Deleted user ID: 73', '165.56.186.85', '2026-03-14 05:05:28'),
(251, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.9', '2026-03-14 05:38:27'),
(252, 4, 'dealer', 'login', 'User logged in successfully', '165.56.186.9', '2026-03-14 05:38:42'),
(253, 2, 'admin', 'login', 'User logged in successfully', '102.208.220.206', '2026-03-14 07:57:35'),
(254, 2, 'admin', 'send_email', 'Sent email to user ID: 67. Subject: Verification ', '102.208.220.200', '2026-03-14 07:59:33'),
(255, 2, 'admin', 'send_email', 'Sent email to user ID: 49. Subject: Property upload ', '102.208.220.203', '2026-03-14 08:02:13'),
(256, 2, 'admin', 'send_email', 'Sent email to user ID: 50. Subject: Property ', '102.208.220.202', '2026-03-14 08:03:54'),
(257, 2, 'admin', 'send_email', 'Sent email to user ID: 66. Subject: Verification ', '102.208.220.203', '2026-03-14 08:05:17'),
(258, 2, 'admin', 'login', 'User logged in successfully', '102.208.220.203', '2026-03-14 08:10:59'),
(259, 2, 'admin', 'login', 'User logged in successfully', '102.208.220.203', '2026-03-14 08:34:18'),
(260, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.235', '2026-03-14 09:38:36'),
(261, 2, 'admin', 'login', 'User logged in successfully', '165.56.66.109', '2026-03-14 10:49:47'),
(262, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.48', '2026-03-14 11:05:42'),
(263, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.48', '2026-03-14 11:22:50'),
(264, 2, 'admin', 'send_email', 'Sent email to user ID: 50. Subject: Verification ', '165.56.186.48', '2026-03-14 11:32:17'),
(265, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.48', '2026-03-14 11:33:39'),
(266, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.31', '2026-03-14 13:04:10'),
(267, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.58', '2026-03-14 13:52:51'),
(268, 2, 'admin', 'login', 'User logged in successfully', '165.57.81.216', '2026-03-14 14:50:01'),
(269, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.220', '2026-03-14 16:35:29'),
(270, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.220', '2026-03-14 17:01:39'),
(271, 4, 'dealer', 'login', 'User logged in successfully', '165.58.129.220', '2026-03-14 17:04:55'),
(272, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.220', '2026-03-14 17:07:56'),
(273, 4, 'dealer', 'login', 'User logged in successfully', '165.58.129.220', '2026-03-14 17:27:54'),
(274, 4, 'dealer', 'login', 'User logged in successfully', '165.58.129.220', '2026-03-14 17:42:21'),
(275, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.220', '2026-03-14 17:45:24'),
(276, 4, 'dealer', 'login', 'User logged in successfully', '165.58.129.220', '2026-03-14 17:48:02'),
(277, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.220', '2026-03-14 18:01:35'),
(278, 4, 'dealer', 'login', 'User logged in successfully', '165.58.129.220', '2026-03-14 18:02:37'),
(279, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.220', '2026-03-14 18:38:35'),
(280, 2, 'admin', 'login', 'User logged in successfully', '102.208.220.203', '2026-03-14 20:24:02'),
(281, 2, 'admin', 'login', 'User logged in successfully', '102.208.220.203', '2026-03-15 05:44:21'),
(282, 4, 'dealer', 'login', 'User logged in successfully', '102.208.220.203', '2026-03-15 05:44:48'),
(283, 2, 'admin', 'login', 'User logged in successfully', '102.208.220.206', '2026-03-15 08:42:01'),
(284, 4, 'dealer', 'login', 'User logged in successfully', '102.208.220.206', '2026-03-15 08:42:54'),
(285, 2, 'admin', 'login', 'User logged in successfully', '102.208.220.206', '2026-03-15 11:12:29'),
(286, 2, 'admin', 'login', 'User logged in successfully', '102.208.220.206', '2026-03-15 12:17:34'),
(287, 2, 'admin', 'login', 'User logged in successfully', '102.208.220.207', '2026-03-15 12:24:39'),
(288, 2, 'admin', 'login', 'User logged in successfully', '102.208.220.206', '2026-03-15 12:38:54'),
(289, 2, 'admin', 'login', 'User logged in successfully', '165.56.66.242', '2026-03-15 15:16:10'),
(290, 2, 'admin', 'login', 'User logged in successfully', '165.56.66.242', '2026-03-15 16:35:55'),
(291, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.191', '2026-03-15 18:07:27'),
(292, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.40', '2026-03-16 08:47:51'),
(293, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.185', '2026-03-16 12:03:15'),
(294, 4, 'dealer', 'login', 'User logged in successfully', '165.56.186.185', '2026-03-16 12:03:37'),
(295, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.185', '2026-03-16 12:06:38'),
(296, 4, 'dealer', 'login', 'User logged in successfully', '165.58.129.31', '2026-03-16 12:12:35'),
(297, 2, 'admin', 'login', 'User logged in successfully', '165.57.81.126', '2026-03-16 17:18:46'),
(298, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.34', '2026-03-16 19:57:06'),
(299, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.132', '2026-03-16 20:50:20'),
(300, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.177', '2026-03-16 21:03:02'),
(301, 4, 'dealer', 'login', 'User logged in successfully', '165.58.129.177', '2026-03-16 21:03:24'),
(302, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.177', '2026-03-16 21:26:49'),
(303, 2, 'admin', 'login', 'User logged in successfully', '165.56.66.201', '2026-03-16 21:45:43'),
(304, 2, 'admin', 'login', 'User logged in successfully', '165.56.66.200', '2026-03-16 22:02:55'),
(305, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.182', '2026-03-17 05:05:58'),
(306, 2, 'admin', 'login', 'User logged in successfully', '165.56.66.175', '2026-03-17 09:23:05'),
(307, 2, 'admin', 'login', 'User logged in successfully', '165.57.81.110', '2026-03-17 11:12:42'),
(308, 4, 'dealer', 'login', 'User logged in successfully', '165.56.186.54', '2026-03-17 13:03:05'),
(309, 2, 'admin', 'login', 'User logged in successfully', '165.56.66.213', '2026-03-17 13:22:04'),
(310, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.113', '2026-03-17 15:26:04'),
(311, 4, 'dealer', 'login', 'User logged in successfully', '165.56.186.113', '2026-03-17 15:26:21'),
(312, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.202', '2026-03-17 17:12:48'),
(313, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.57', '2026-03-17 20:19:10'),
(314, 2, 'admin', 'login', 'User logged in successfully', '165.56.66.128', '2026-03-18 09:53:57'),
(315, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.65', '2026-03-18 13:14:04'),
(316, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.217', '2026-03-18 14:47:51'),
(317, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.217', '2026-03-18 15:33:16'),
(318, 2, 'admin', 'login', 'User logged in successfully', '45.215.249.159', '2026-03-18 20:17:24'),
(319, 4, 'dealer', 'login', 'User logged in successfully', '45.215.224.233', '2026-03-18 20:34:25'),
(320, 2, 'admin', 'login', 'User logged in successfully', '45.215.224.233', '2026-03-18 21:13:07'),
(321, 2, 'admin', 'login', 'User logged in successfully', '165.57.81.124', '2026-03-19 05:42:03'),
(322, 2, 'admin', 'login', 'User logged in successfully', '165.57.81.130', '2026-03-19 10:21:55'),
(323, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.224', '2026-03-19 15:12:36'),
(324, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.101', '2026-03-19 19:24:31'),
(325, 2, 'admin', 'login', 'User logged in successfully', '165.57.81.41', '2026-03-20 05:45:02'),
(326, NULL, 'user', 'register', 'New user registered: pfnfjtvv@immenseignite.info (user)', '212.192.28.198', '2026-03-20 08:03:12'),
(327, NULL, 'user', 'register', 'New user registered: olxfymfl@immenseignite.info (user)', '45.43.163.244', '2026-03-20 08:11:53'),
(328, NULL, 'user', 'register', 'New user registered: fuzzyball3188@msn.com (user)', '194.116.236.215', '2026-03-20 08:12:46'),
(329, NULL, 'user', 'register', 'New user registered: mnelson55@fordham.edu (user)', '194.116.236.215', '2026-03-20 08:12:47'),
(330, NULL, 'user', 'register', 'New user registered: daria.schevchuk@gmail.com (user)', '45.141.148.148', '2026-03-20 08:26:32'),
(331, NULL, 'user', 'register', 'New user registered: ctewes@comcast.net (user)', '45.141.148.148', '2026-03-20 08:26:33'),
(332, NULL, 'user', 'register', 'New user registered: megan.hulme@live.co.uk (user)', '216.9.225.89', '2026-03-20 09:06:36'),
(333, NULL, 'user', 'register', 'New user registered: shaiyue@hotmail.com (user)', '31.40.204.182', '2026-03-20 09:24:53'),
(334, NULL, 'user', 'register', 'New user registered: katelynore@gmail.com (user)', '31.40.204.182', '2026-03-20 09:25:12'),
(335, NULL, 'user', 'register', 'New user registered: caline.is@gmail.com (user)', '78.108.218.142', '2026-03-20 09:40:48'),
(336, NULL, 'user', 'register', 'New user registered: alicewiswell@gmail.com (user)', '78.108.218.142', '2026-03-20 09:40:48'),
(337, NULL, 'user', 'register', 'New user registered: rickjmcmichael@gmail.com (user)', '45.43.163.244', '2026-03-20 09:57:13'),
(338, NULL, 'user', 'register', 'New user registered: cbsweet@gmail.com (user)', '45.43.163.244', '2026-03-20 09:57:40'),
(339, NULL, 'user', 'register', 'New user registered: levi.brower@outlook.com (user)', '216.9.225.163', '2026-03-20 10:13:31'),
(340, NULL, 'user', 'register', 'New user registered: locklearjm@aol.com (user)', '216.9.225.163', '2026-03-20 10:13:39'),
(341, NULL, 'user', 'register', 'New user registered: mollyruben@gmail.com (user)', '198.46.154.21', '2026-03-20 10:31:28'),
(342, NULL, 'user', 'register', 'New user registered: hmbsam@gmail.com (user)', '212.192.28.198', '2026-03-20 10:46:56'),
(343, NULL, 'user', 'register', 'New user registered: bfrink77@yahoo.com (user)', '192.210.198.197', '2026-03-20 11:02:18'),
(344, NULL, 'user', 'register', 'New user registered: awheat@polsinelli.com (user)', '192.210.198.197', '2026-03-20 11:02:22'),
(345, NULL, 'user', 'register', 'New user registered: falcon97@aol.com (user)', '107.173.160.167', '2026-03-20 11:29:18'),
(346, NULL, 'user', 'register', 'New user registered: crawkin@gmail.com (user)', '107.173.160.167', '2026-03-20 11:30:39'),
(347, NULL, 'user', 'register', 'New user registered: anetarons3653@outlook.com (user)', '198.12.69.93', '2026-03-20 12:19:54'),
(348, NULL, 'user', 'register', 'New user registered: michelleheck@hotmail.com (user)', '198.12.69.93', '2026-03-20 12:20:49'),
(349, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.25', '2026-03-20 12:20:58'),
(350, 2, 'admin', 'delete_user', 'Deleted user ID: 74', '165.58.129.25', '2026-03-20 12:21:41'),
(351, 2, 'admin', 'delete_user', 'Deleted user ID: 96', '165.58.129.25', '2026-03-20 12:21:47'),
(352, 2, 'admin', 'delete_user', 'Deleted user ID: 95', '165.58.129.25', '2026-03-20 12:21:51'),
(353, 2, 'admin', 'delete_user', 'Deleted user ID: 93', '165.58.129.25', '2026-03-20 12:22:06'),
(354, 2, 'admin', 'delete_user', 'Deleted user ID: 75', '165.58.129.25', '2026-03-20 12:22:31'),
(355, 2, 'admin', 'ban_user', 'Changed ban status for user ID: 82 to 1', '165.58.129.25', '2026-03-20 12:22:46'),
(356, 2, 'admin', 'ban_user', 'Changed ban status for user ID: 84 to 1', '165.58.129.25', '2026-03-20 12:22:47'),
(357, 2, 'admin', 'ban_user', 'Changed ban status for user ID: 76 to 1', '165.58.129.25', '2026-03-20 12:22:57'),
(358, 2, 'admin', 'ban_user', 'Changed ban status for user ID: 77 to 1', '165.58.129.25', '2026-03-20 12:23:22'),
(359, 2, 'admin', 'delete_user', 'Deleted user ID: 94', '165.58.129.25', '2026-03-20 12:23:28'),
(360, 2, 'admin', 'delete_user', 'Deleted user ID: 67', '165.58.129.25', '2026-03-20 12:23:40'),
(361, 2, 'admin', 'ban_user', 'Changed ban status for user ID: 78 to 1', '165.58.129.25', '2026-03-20 12:23:56'),
(362, 2, 'admin', 'delete_user', 'Deleted user ID: 92', '165.58.129.25', '2026-03-20 12:24:01'),
(363, 2, 'admin', 'delete_user', 'Deleted user ID: 91', '165.58.129.25', '2026-03-20 12:24:04'),
(364, 2, 'admin', 'delete_user', 'Deleted user ID: 90', '165.58.129.25', '2026-03-20 12:24:08'),
(365, 2, 'admin', 'delete_user', 'Deleted user ID: 89', '165.58.129.25', '2026-03-20 12:24:11'),
(366, 2, 'admin', 'delete_user', 'Deleted user ID: 88', '165.58.129.25', '2026-03-20 12:24:15'),
(367, 2, 'admin', 'delete_user', 'Deleted user ID: 87', '165.58.129.25', '2026-03-20 12:24:18'),
(368, 2, 'admin', 'delete_user', 'Deleted user ID: 76', '165.58.129.25', '2026-03-20 12:24:26'),
(369, 2, 'admin', 'delete_user', 'Deleted user ID: 78', '165.58.129.25', '2026-03-20 12:24:37'),
(370, 2, 'admin', 'delete_user', 'Deleted user ID: 86', '165.58.129.25', '2026-03-20 12:24:46'),
(371, 2, 'admin', 'delete_user', 'Deleted user ID: 85', '165.58.129.25', '2026-03-20 12:24:58'),
(372, 2, 'admin', 'delete_user', 'Deleted user ID: 79', '165.58.129.25', '2026-03-20 12:25:06'),
(373, 2, 'admin', 'ban_user', 'Changed ban status for user ID: 80 to 1', '165.58.129.25', '2026-03-20 12:25:30'),
(374, 2, 'admin', 'ban_user', 'Changed ban status for user ID: 83 to 1', '165.58.129.25', '2026-03-20 12:25:37'),
(375, 2, 'admin', 'ban_user', 'Changed ban status for user ID: 81 to 1', '165.58.129.25', '2026-03-20 12:25:53'),
(376, 4, 'dealer', 'login', 'User logged in successfully', '165.58.129.25', '2026-03-20 12:26:36'),
(377, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.25', '2026-03-20 12:26:58'),
(378, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.25', '2026-03-20 12:47:40'),
(379, NULL, 'user', 'register', 'New user registered: jdavis@atedsn.com (user)', '216.9.224.107', '2026-03-20 13:50:12'),
(380, NULL, 'user', 'register', 'New user registered: jmjfam@gmail.com (user)', '216.9.224.107', '2026-03-20 13:50:29'),
(381, NULL, 'user', 'register', 'New user registered: dcrider0776@msn.com (user)', '192.210.150.198', '2026-03-20 14:27:21'),
(382, NULL, 'user', 'register', 'New user registered: angehof@gmail.com (user)', '192.210.150.198', '2026-03-20 14:27:22'),
(383, NULL, 'user', 'register', 'New user registered: sjbalks@gmail.com (user)', '192.210.198.197', '2026-03-20 14:54:30'),
(384, NULL, 'user', 'register', 'New user registered: sales@audioinnovators.com (user)', '192.210.198.197', '2026-03-20 14:54:31'),
(385, NULL, 'user', 'register', 'New user registered: fcadelagarza@gmail.com (user)', '216.9.225.89', '2026-03-20 15:22:24'),
(386, NULL, 'user', 'register', 'New user registered: messywigs@rogers.com (user)', '216.9.225.89', '2026-03-20 15:22:25'),
(387, 4, 'dealer', 'login', 'User logged in successfully', '165.56.186.128', '2026-03-20 16:04:30'),
(388, NULL, 'user', 'register', 'New user registered: srottman@comcast.net (user)', '31.40.204.182', '2026-03-20 16:06:30'),
(389, NULL, 'user', 'register', 'New user registered: misscherrikitty@yahoo.com (user)', '31.40.204.182', '2026-03-20 16:06:36'),
(390, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.128', '2026-03-20 17:29:02'),
(391, 2, 'admin', 'delete_user', 'Deleted user ID: 97', '165.56.186.128', '2026-03-20 17:29:40'),
(392, 2, 'admin', 'delete_user', 'Deleted user ID: 106', '165.56.186.128', '2026-03-20 17:29:46'),
(393, 2, 'admin', 'delete_user', 'Deleted user ID: 105', '165.56.186.128', '2026-03-20 17:29:52'),
(394, 2, 'admin', 'delete_user', 'Deleted user ID: 104', '165.56.186.128', '2026-03-20 17:29:57'),
(395, 2, 'admin', 'delete_user', 'Deleted user ID: 103', '165.56.186.128', '2026-03-20 17:30:03'),
(396, 2, 'admin', 'delete_user', 'Deleted user ID: 102', '165.56.186.128', '2026-03-20 17:30:12'),
(397, 2, 'admin', 'delete_user', 'Deleted user ID: 98', '165.56.186.128', '2026-03-20 17:30:21'),
(398, 2, 'admin', 'delete_user', 'Deleted user ID: 101', '165.56.186.128', '2026-03-20 17:30:25'),
(399, 2, 'admin', 'delete_user', 'Deleted user ID: 100', '165.56.186.128', '2026-03-20 17:30:30'),
(400, 2, 'admin', 'delete_user', 'Deleted user ID: 99', '165.56.186.128', '2026-03-20 17:30:36'),
(401, NULL, 'user', 'register', 'New user registered: mfm@extreme-endeavors.com (user)', '31.40.204.182', '2026-03-20 17:39:40'),
(402, NULL, 'user', 'register', 'New user registered: hdpapa57@yahoo.com (user)', '31.40.204.182', '2026-03-20 17:39:46'),
(403, NULL, 'user', 'register', 'New user registered: skdk911@comcast.net (user)', '216.9.225.89', '2026-03-20 18:29:13'),
(404, NULL, 'user', 'register', 'New user registered: karenmacd@telus.net (user)', '216.9.225.89', '2026-03-20 18:29:13'),
(405, NULL, 'user', 'register', 'New user registered: christian.hang@gmail.com (user)', '198.46.154.22', '2026-03-20 19:17:11'),
(406, NULL, 'user', 'register', 'New user registered: collegeangela@gmail.com (user)', '198.46.154.22', '2026-03-20 19:17:41'),
(407, NULL, 'user', 'register', 'New user registered: nhatfield2302@gmail.com (user)', '216.9.225.89', '2026-03-20 20:20:34'),
(408, NULL, 'user', 'register', 'New user registered: arturo.manzanares8@yahoo.com (user)', '216.9.225.89', '2026-03-20 20:20:34'),
(409, NULL, 'user', 'register', 'New user registered: langworthy.john@gmail.com (user)', '78.108.218.142', '2026-03-20 21:16:17'),
(410, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.56', '2026-03-20 21:33:39'),
(411, 2, 'admin', 'delete_user', 'Deleted user ID: 108', '165.56.186.56', '2026-03-20 21:33:59'),
(412, 2, 'admin', 'delete_user', 'Deleted user ID: 83', '165.56.186.56', '2026-03-20 21:34:08'),
(413, 2, 'admin', 'delete_user', 'Deleted user ID: 107', '165.56.186.56', '2026-03-20 21:34:16'),
(414, 2, 'admin', 'delete_user', 'Deleted user ID: 115', '165.56.186.56', '2026-03-20 21:34:31'),
(415, 2, 'admin', 'delete_user', 'Deleted user ID: 113', '165.56.186.56', '2026-03-20 21:34:34'),
(416, 2, 'admin', 'delete_user', 'Deleted user ID: 114', '165.56.186.56', '2026-03-20 21:34:37'),
(417, 2, 'admin', 'delete_user', 'Deleted user ID: 112', '165.56.186.56', '2026-03-20 21:34:39'),
(418, NULL, 'user', 'register', 'New user registered: langworthy.john@gmail.com (user)', '216.9.225.163', '2026-03-20 21:51:25'),
(419, NULL, 'user', 'register', 'New user registered: nhatfield2302@gmail.com (user)', '216.9.225.163', '2026-03-20 21:51:34'),
(420, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.56', '2026-03-20 21:55:22'),
(421, 2, 'admin', 'delete_user', 'Deleted user ID: 117', '165.56.186.56', '2026-03-20 21:55:37'),
(422, 2, 'admin', 'delete_user', 'Deleted user ID: 116', '165.56.186.56', '2026-03-20 21:55:41'),
(423, 2, 'admin', 'delete_user', 'Deleted user ID: 111', '165.56.186.56', '2026-03-20 21:55:45'),
(424, 2, 'admin', 'delete_user', 'Deleted user ID: 109', '165.56.186.56', '2026-03-20 21:55:52'),
(425, 2, 'admin', 'delete_user', 'Deleted user ID: 110', '165.56.186.56', '2026-03-20 21:55:55'),
(426, 2, 'admin', 'delete_user', 'Deleted user ID: 111', '165.56.186.56', '2026-03-20 22:03:03'),
(427, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.56', '2026-03-20 22:03:42'),
(428, NULL, 'user', 'register', 'New user registered: chisalavudo@gmail.com (user)', '165.56.186.56', '2026-03-20 22:06:49'),
(429, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.56', '2026-03-20 22:10:58'),
(430, 2, 'admin', 'delete_user', 'Deleted user ID: 84', '165.56.186.56', '2026-03-20 22:11:10'),
(431, 2, 'admin', 'delete_user', 'Deleted user ID: 82', '165.56.186.56', '2026-03-20 22:11:14'),
(432, 2, 'admin', 'delete_user', 'Deleted user ID: 81', '165.56.186.56', '2026-03-20 22:11:19'),
(433, 2, 'admin', 'delete_user', 'Deleted user ID: 118', '165.56.186.56', '2026-03-20 22:11:24'),
(434, 2, 'admin', 'delete_user', 'Deleted user ID: 77', '165.56.186.56', '2026-03-20 22:11:28'),
(435, 2, 'admin', 'delete_user', 'Deleted user ID: 80', '165.56.186.56', '2026-03-20 22:11:32'),
(436, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.56', '2026-03-20 22:14:26'),
(437, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.56', '2026-03-20 22:28:08'),
(438, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.56', '2026-03-21 05:38:08'),
(439, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.56', '2026-03-21 06:04:39'),
(440, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.56', '2026-03-21 06:18:32'),
(441, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.56', '2026-03-21 07:24:48'),
(442, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.145', '2026-03-21 08:25:57'),
(443, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.131', '2026-03-21 11:06:38'),
(444, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.171', '2026-03-21 12:01:42'),
(445, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.247', '2026-03-21 14:35:17'),
(446, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.144', '2026-03-21 17:42:59'),
(447, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.144', '2026-03-21 17:51:07'),
(448, 4, 'dealer', 'login', 'User logged in successfully', '165.58.129.144', '2026-03-21 17:51:31'),
(449, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.132', '2026-03-21 20:19:54'),
(450, 2, 'admin', 'login', 'User logged in successfully', '165.56.66.245', '2026-03-22 06:42:02'),
(451, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.216', '2026-03-22 14:24:26'),
(452, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.138', '2026-03-22 15:47:04'),
(453, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.33', '2026-03-22 16:50:05'),
(454, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.218', '2026-03-22 22:09:38'),
(455, 2, 'admin', 'login', 'User logged in successfully', '165.56.186.190', '2026-03-23 07:49:46'),
(456, 2, 'admin', 'login', 'User logged in successfully', '165.56.66.202', '2026-03-23 08:48:02'),
(457, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.30', '2026-03-23 09:57:51'),
(458, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.111', '2026-03-23 16:45:08'),
(459, 4, 'dealer', 'login', 'User logged in successfully', '165.58.129.111', '2026-03-23 16:51:56'),
(460, 2, 'admin', 'login', 'User logged in successfully', '165.58.129.111', '2026-03-23 16:54:11');

-- --------------------------------------------------------

--
-- Table structure for table `dealers`
--

CREATE TABLE `dealers` (
  `user_id` int(11) NOT NULL,
  `company_name` varchar(100) DEFAULT NULL,
  `office_address` text DEFAULT NULL,
  `bio` text DEFAULT NULL,
  `subscription_status` enum('active','expired','none') DEFAULT 'none',
  `subscription_expiry` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `dealers`
--

INSERT INTO `dealers` (`user_id`, `company_name`, `office_address`, `bio`, `subscription_status`, `subscription_expiry`) VALUES
(4, NULL, NULL, NULL, 'active', '2026-04-05 17:32:33'),
(38, NULL, NULL, NULL, 'active', '2026-03-31 00:42:02'),
(49, NULL, NULL, NULL, 'active', '2026-04-02 08:23:23'),
(50, NULL, NULL, NULL, 'active', '2026-04-04 20:41:52'),
(63, NULL, NULL, NULL, '', '2026-04-05 04:00:00'),
(66, NULL, NULL, NULL, 'active', '2026-04-06 14:32:40');

-- --------------------------------------------------------

--
-- Table structure for table `leads`
--

CREATE TABLE `leads` (
  `id` int(11) NOT NULL,
  `property_id` int(11) NOT NULL,
  `dealer_id` int(11) NOT NULL,
  `name` varchar(255) NOT NULL,
  `email` varchar(255) NOT NULL,
  `phone` varchar(50) DEFAULT NULL,
  `message` text DEFAULT NULL,
  `created_at` datetime DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `leads`
--

INSERT INTO `leads` (`id`, `property_id`, `dealer_id`, `name`, `email`, `phone`, `message`, `created_at`) VALUES
(1, 7, 4, 'Lackson Chisala', 'chisalaluckykb5@gmail.com', '0771355473', 'I&#039;m interested in this property.', '2026-02-25 15:19:55'),
(2, 7, 4, 'Lackson Chisala', 'chisalaluckyk5@gmail.com', '0771355473', 'I&#039;m interested in this property.', '2026-02-25 15:54:00'),
(3, 7, 4, 'ZAP', 'foo-bar@example.com', 'ZAP', 'I&#039;m interested in this property.', '2026-02-26 06:08:47'),
(4, 3, 5, 'ZAP', 'foo-bar@example.com', 'ZAP', 'I&#039;m interested in this property.', '2026-02-26 06:08:48'),
(5, 6, 4, 'ZAP', 'foo-bar@example.com', 'ZAP', 'I&#039;m interested in this property.', '2026-02-26 06:08:48'),
(6, 12, 50, 'We&#039;re are you located', 'mutale@gmail.com', '0771355475', 'I&#039;m interested in this property.', '2026-03-07 13:04:41'),
(7, 9, 4, 'Lackson Chisala', 'chisalaluckyk5@gmail.com', '0771355473', 'I&#039;m interested in this property.', '2026-03-07 13:05:13'),
(8, 9, 4, 'Mutinta Muyamwa', 'muyamwaprincess@gmail.com', '0972508280', 'I&#039;m interested in this property. Is it available?', '2026-03-08 04:35:09'),
(9, 11, 4, 'SxrphbWygFFalaHsLe', 'i.pine.qo.y.o.2.0@gmail.com', '7831123436', 'I&#039;m interested in this property.', '2026-03-11 11:59:13'),
(10, 11, 4, 'WJvuodshHxBwmteb', 'aja.l.i.va.gosi5.36@gmail.com', '5612923983', 'I&#039;m interested in this property.', '2026-03-13 22:45:11');

-- --------------------------------------------------------

--
-- Table structure for table `notifications`
--

CREATE TABLE `notifications` (
  `id` int(11) NOT NULL,
  `title` varchar(255) NOT NULL,
  `message` text NOT NULL,
  `type` enum('info','warning','danger','success') DEFAULT 'info',
  `target_role` enum('all','dealer','user') DEFAULT 'all',
  `is_active` tinyint(1) DEFAULT 1,
  `created_by` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `notifications`
--

INSERT INTO `notifications` (`id`, `title`, `message`, `type`, `target_role`, `is_active`, `created_by`, `created_at`) VALUES
(1, 'app', 'app coming soon', 'info', 'dealer', 1, 2, '2026-03-14 17:27:32'),
(2, 'imporant', 'Did you know has landlord you can manage your tenants with just a single tap, click manage on the side bar', 'info', 'dealer', 1, 2, '2026-03-14 17:47:40');

-- --------------------------------------------------------

--
-- Table structure for table `notification_reads`
--

CREATE TABLE `notification_reads` (
  `id` int(11) NOT NULL,
  `notification_id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `read_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `notification_reads`
--

INSERT INTO `notification_reads` (`id`, `notification_id`, `user_id`, `read_at`) VALUES
(1, 1, 4, '2026-03-14 17:44:45'),
(2, 2, 4, '2026-03-15 05:44:58'),
(3, 1, 66, '2026-03-15 11:27:52'),
(4, 2, 66, '2026-03-15 11:28:03');

-- --------------------------------------------------------

--
-- Table structure for table `properties`
--

CREATE TABLE `properties` (
  `id` int(11) NOT NULL,
  `dealer_id` int(11) NOT NULL,
  `title` varchar(255) NOT NULL,
  `description` text DEFAULT NULL,
  `price` decimal(10,2) NOT NULL,
  `currency` varchar(10) DEFAULT 'ZMW',
  `bedrooms` int(11) DEFAULT NULL,
  `bathrooms` int(11) DEFAULT NULL,
  `rooms` int(11) DEFAULT NULL,
  `size_sqm` decimal(10,2) DEFAULT NULL,
  `property_type` enum('house','apartment','flat','boarding_house','land','commercial','wedding_venue','restaurant','lodge','studio','cottage','manor') NOT NULL DEFAULT 'house',
  `listing_purpose` enum('rent','sale','booking','service') NOT NULL DEFAULT 'rent',
  `location` varchar(255) NOT NULL,
  `city` varchar(100) DEFAULT NULL,
  `country` varchar(100) DEFAULT NULL,
  `latitude` decimal(10,8) DEFAULT NULL,
  `longitude` decimal(11,8) DEFAULT NULL,
  `status` enum('available','rented') DEFAULT 'available',
  `verification_image` varchar(255) DEFAULT NULL,
  `is_verified` tinyint(1) DEFAULT 0,
  `amenities` text DEFAULT NULL,
  `video_url` varchar(255) DEFAULT NULL,
  `views` int(11) DEFAULT 0,
  `is_featured` tinyint(1) DEFAULT 0,
  `is_boosted` tinyint(1) DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `capacity` int(11) DEFAULT NULL,
  `people_per_room` int(11) DEFAULT NULL,
  `event_type` varchar(255) DEFAULT NULL,
  `catering_available` tinyint(1) DEFAULT 0,
  `equipment_available` tinyint(1) DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `properties`
--

INSERT INTO `properties` (`id`, `dealer_id`, `title`, `description`, `price`, `currency`, `bedrooms`, `bathrooms`, `rooms`, `size_sqm`, `property_type`, `listing_purpose`, `location`, `city`, `country`, `latitude`, `longitude`, `status`, `verification_image`, `is_verified`, `amenities`, `video_url`, `views`, `is_featured`, `is_boosted`, `created_at`, `capacity`, `people_per_room`, `event_type`, `catering_available`, `equipment_available`) VALUES
(6, 4, 'Chunga hill', 'Very neat ', 2500.00, 'ZMW', 3, 2, 6, 8.00, 'flat', 'rent', '257', 'Lusaka', 'Zambia', -15.37027407, 28.29425812, 'available', NULL, 1, '', '', 205, 1, 0, '2026-02-24 12:38:43', NULL, NULL, NULL, 0, 0),
(7, 4, 'Chalala ', 'Very neat', 5800.00, 'ZMW', 4, 3, 10, 80.00, 'house', 'rent', 'Chalala mall', 'Chipata', 'Zambia', -15.46459998, 28.34266663, 'available', NULL, 1, 'Wifi, solar', '', 260, 1, 0, '2026-02-24 12:40:09', NULL, NULL, NULL, 0, 0),
(9, 4, 'Neat house ', 'This house it&amp;#039;s very neat.\r\nHas everything you need ', 8000.00, 'ZMW', 4, 2, 8, 100.00, 'house', 'rent', 'Chalala mall', 'Lusaka', 'Zambia', NULL, NULL, 'available', NULL, 1, '', '', 160, 1, 0, '2026-03-02 15:43:35', NULL, NULL, NULL, 0, 0),
(10, 4, 'Weddings', 'Very ckean', 4800.00, 'ZMW', 0, 0, 8, 8000.00, 'wedding_venue', 'service', 'Lusaka', 'Lusaka', 'Zambia', -15.37810204, 28.32848628, 'available', NULL, 1, '', '', 90, 1, 0, '2026-03-02 23:29:41', 5000, NULL, 'Weddings', 1, 1),
(11, 4, 'Salama', 'Bmnbvvccc', 40.00, 'ZMW', 2, 8, 10, 7.00, 'restaurant', 'service', 'Matero', 'Lusaka', 'Zambia', -15.37738230, 28.26143320, 'available', NULL, 1, '', '', 102, 1, 0, '2026-03-02 23:32:59', 5000, NULL, 'family', 1, 1),
(12, 50, 'Parkview Boarding house ', '', 850.00, 'ZMW', 2, 2, 3, 0.00, 'boarding_house', 'rent', 'Parkview boarding house ', 'Lusaka', 'Zambia', -15.41746306, 28.28246176, 'available', NULL, 1, '', '', 100, 0, 0, '2026-03-05 16:48:33', NULL, 6, NULL, 0, 0),
(13, 50, 'Parkview Boarding house ', '', 850.00, 'ZMW', 2, 2, 3, 0.00, 'boarding_house', 'rent', 'Parkview boarding house ', 'Lusaka', 'Zambia', -15.41746306, 28.28246176, 'available', NULL, 1, '', '', 88, 0, 0, '2026-03-05 16:48:33', NULL, 6, NULL, 0, 0);

-- --------------------------------------------------------

--
-- Table structure for table `property_images`
--

CREATE TABLE `property_images` (
  `id` int(11) NOT NULL,
  `property_id` int(11) NOT NULL,
  `image_path` varchar(255) NOT NULL,
  `is_main` tinyint(1) DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `type` enum('image','video') DEFAULT 'image'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `property_images`
--

INSERT INTO `property_images` (`id`, `property_id`, `image_path`, `is_main`, `created_at`, `type`) VALUES
(21, 6, 'assets/images/properties/prop_6_699d9be777772.jpg', 0, '2026-02-24 12:39:03', 'image'),
(22, 6, 'assets/images/properties/prop_6_699d9be777c87.jpg', 0, '2026-02-24 12:39:03', 'image'),
(23, 7, 'assets/images/properties/prop_7_699d9c37a7d88.jpg', 0, '2026-02-24 12:40:23', 'image'),
(24, 7, 'assets/images/properties/prop_7_699d9c37a8196.jpg', 0, '2026-02-24 12:40:23', 'image'),
(25, 7, 'assets/images/properties/vid_7_699ed49301954.mp4', 0, '2026-02-25 10:53:07', 'video'),
(27, 9, 'assets/images/properties/prop_9_69a5b0362987b.jpg', 0, '2026-03-02 15:43:50', 'image'),
(28, 10, 'assets/images/properties/prop_10_69a61d7343b7c.jpg', 0, '2026-03-02 23:29:55', 'image'),
(29, 11, 'assets/images/properties/prop_11_69a61e382e9ae.jpg', 0, '2026-03-02 23:33:12', 'image');

-- --------------------------------------------------------

--
-- Table structure for table `property_reports`
--

CREATE TABLE `property_reports` (
  `id` int(11) NOT NULL,
  `property_id` int(11) NOT NULL,
  `user_id` int(11) DEFAULT NULL,
  `reason` varchar(100) NOT NULL,
  `details` text DEFAULT NULL,
  `status` enum('pending','reviewed','dismissed') DEFAULT 'pending',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `property_reports`
--

INSERT INTO `property_reports` (`id`, `property_id`, `user_id`, `reason`, `details`, `status`, `created_at`) VALUES
(2, 7, NULL, 'fraud', '', 'pending', '2026-02-26 11:08:47'),
(4, 6, NULL, 'fraud', '', 'dismissed', '2026-02-26 11:08:48');

-- --------------------------------------------------------

--
-- Table structure for table `rentals`
--

CREATE TABLE `rentals` (
  `id` int(11) NOT NULL,
  `property_id` int(11) NOT NULL,
  `room_number` varchar(50) DEFAULT NULL,
  `dealer_id` int(11) NOT NULL,
  `tenant_id` int(11) NOT NULL,
  `status` enum('active','ended','pending') DEFAULT 'active',
  `start_date` date NOT NULL,
  `end_date` date DEFAULT NULL,
  `rent_amount` decimal(10,2) NOT NULL,
  `currency` varchar(3) DEFAULT 'ZMW',
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `payment_reference` varchar(20) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `rent_payments`
--

CREATE TABLE `rent_payments` (
  `id` int(11) NOT NULL,
  `rental_id` int(11) NOT NULL,
  `tenant_id` int(11) NOT NULL,
  `month_year` varchar(20) NOT NULL,
  `amount` decimal(10,2) NOT NULL,
  `currency` varchar(3) DEFAULT 'ZMW',
  `proof_file` varchar(255) DEFAULT NULL,
  `status` enum('pending','approved','rejected') DEFAULT 'pending',
  `dealer_notes` text DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  `payment_method` enum('cash','bank_transfer','mobile_money') DEFAULT 'bank_transfer',
  `months_paid` int(11) DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `reports`
--

CREATE TABLE `reports` (
  `id` int(11) NOT NULL,
  `property_id` int(11) NOT NULL,
  `user_id` int(11) DEFAULT NULL,
  `reason` text NOT NULL,
  `status` enum('pending','reviewed','resolved') DEFAULT 'pending',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `saved_properties`
--

CREATE TABLE `saved_properties` (
  `id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `property_id` int(11) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `settings`
--

CREATE TABLE `settings` (
  `id` int(11) NOT NULL,
  `setting_key` varchar(50) NOT NULL,
  `setting_value` varchar(255) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `settings`
--

INSERT INTO `settings` (`id`, `setting_key`, `setting_value`) VALUES
(1, 'enable_free_trial', '1'),
(2, 'free_trial_duration', '30');

-- --------------------------------------------------------

--
-- Table structure for table `subscriptions`
--

CREATE TABLE `subscriptions` (
  `id` int(11) NOT NULL,
  `dealer_id` int(11) NOT NULL,
  `amount` decimal(10,2) NOT NULL,
  `currency` varchar(10) NOT NULL,
  `payment_method` varchar(50) DEFAULT NULL,
  `transaction_id` varchar(100) DEFAULT NULL,
  `status` enum('pending','completed','failed') DEFAULT 'pending',
  `start_date` timestamp NOT NULL DEFAULT current_timestamp(),
  `end_date` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `tenancy_history`
--

CREATE TABLE `tenancy_history` (
  `id` int(11) NOT NULL,
  `property_id` int(11) NOT NULL,
  `tenant_name` varchar(255) NOT NULL,
  `start_date` date NOT NULL,
  `end_date` date NOT NULL,
  `condition_start` text DEFAULT NULL,
  `condition_end` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `transactions`
--

CREATE TABLE `transactions` (
  `id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `reference` varchar(255) NOT NULL,
  `lenco_reference` varchar(255) DEFAULT NULL,
  `amount` decimal(10,2) NOT NULL,
  `currency` varchar(10) DEFAULT 'ZMW',
  `status` varchar(50) NOT NULL,
  `message` text DEFAULT NULL,
  `payment_method` varchar(50) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `transactions`
--

INSERT INTO `transactions` (`id`, `user_id`, `reference`, `lenco_reference`, `amount`, `currency`, `status`, `message`, `payment_method`, `created_at`, `updated_at`) VALUES
(1, 4, 'SUB-1771937278534', '2605514696', 20.00, 'ZMW', 'successful', 'Synced from Lenco: Successful', 'mobile-money', '2026-02-24 12:48:34', '2026-02-26 13:11:46'),
(2, 4, 'SUB-1771938055904', '2605504827', 20.00, 'ZMW', 'successful', 'Synced from Lenco: Successful', 'mobile-money', '2026-02-24 13:01:38', '2026-03-06 13:32:33');

-- --------------------------------------------------------

--
-- Table structure for table `users`
--

CREATE TABLE `users` (
  `id` int(11) NOT NULL,
  `name` varchar(100) NOT NULL,
  `email` varchar(100) NOT NULL,
  `password` varchar(255) DEFAULT NULL,
  `phone` varchar(20) DEFAULT NULL,
  `role` enum('user','dealer','admin') DEFAULT 'user',
  `whatsapp_number` varchar(20) DEFAULT NULL,
  `profile_image` varchar(255) DEFAULT NULL,
  `is_verified` tinyint(1) DEFAULT 0,
  `identity_verified` tinyint(4) DEFAULT 0,
  `is_banned` tinyint(1) DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `verification_token` varchar(255) DEFAULT NULL,
  `token_expiry` timestamp NULL DEFAULT NULL,
  `google_id` varchar(255) DEFAULT NULL,
  `reset_token` varchar(255) DEFAULT NULL,
  `reset_expires` datetime DEFAULT NULL,
  `bank_details` text DEFAULT NULL,
  `verification_doc` varchar(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `users`
--

INSERT INTO `users` (`id`, `name`, `email`, `password`, `phone`, `role`, `whatsapp_number`, `profile_image`, `is_verified`, `identity_verified`, `is_banned`, `created_at`, `verification_token`, `token_expiry`, `google_id`, `reset_token`, `reset_expires`, `bank_details`, `verification_doc`) VALUES
(2, 'System Admin', 'admin@luxestay.com', '$2y$12$NkG7PM9z.L2PzQBLbISc1uo7lEjz7gsz8gCPTgCPrLEf2688OBG4y', NULL, 'admin', NULL, NULL, 0, 1, 0, '2026-02-24 07:54:48', NULL, NULL, NULL, '924ddc4524c6fe6103a3078943b130338d9f73813383d747f7abf8ba8affa6c9', '2026-02-24 10:59:54', NULL, NULL),
(4, 'Lackson Chisala', 'chisalaluckson70@gmail.com', '$2y$12$QMF7st4Z2lIYiJbeRdlxw.kw72I.gM95OJHJYK9heifMcAJosoqDu', '0771355473', 'dealer', '0771355473', 'assets/images/users/profile_4_1771946943.jpg', 1, 1, 0, '2026-02-24 10:02:09', NULL, NULL, NULL, '27dc6cec847b4570c4792bff1c9e7f7d879d6d97fafa7f8b5cfe5d6ff094225b', '2026-03-14 18:07:02', '077082884', NULL),
(38, 'Joseph Kashikite', 'joekashikite@gmail.com', '$2y$12$Rvyrr5Zg95B3Jr2dNtOQKOwxvxP3nfG68U64Q5LjnUl2Q0eDaxzE2', '0973042237', 'dealer', '', NULL, 1, 0, 0, '2026-02-28 20:42:02', '83193dd4a9ae95e22716e4932798bff7a30a3ca91a3bb3e19b07c4e403baa3bc', '2026-03-01 01:45:02', NULL, '022b776cae5d9d5f91c254734353433b1cb3632b2aceb98f3c186cda330b4a4f', '2026-02-28 22:29:32', NULL, NULL),
(47, 'Nkhata Frank', 'frank.t.r.b59@gmail.com', '$2y$12$viqVTzF4appz3DMkojHjvegIT9K3gpS6j8HADZBtTGjS6ECMLUJxu', '0972232932', 'user', '', NULL, 1, 0, 0, '2026-03-02 11:46:37', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(49, 'John Doe', 'deleyi5268@ostahie.com', '$2y$12$tA7Z1f9bMxj/wpwHYl/RHeOTPGYwobbOzWyL.3/ScxOS52TyN3G9u', '0970000000', 'dealer', '', NULL, 1, 1, 0, '2026-03-03 04:23:23', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(50, 'Danny Nkhata', 'dannynkhata6@gmail.com', '$2y$12$n.4OIuEZ0LyEH5N5mK1fv.kvKLTU7hp70jl5WlTjDDbTYvjOVAVt2', '0973795625', 'dealer', '', NULL, 1, 1, 0, '2026-03-05 16:41:52', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(63, 'Gerald Shamulanga', 'gggeraldshamulanga@gmail.com', '$2y$12$UFUQ3rJlRP2HwzwsS5x1puRlAh5B1N2PiPdd2zFqI2Od8RbfVvQjW', '0770766345', 'dealer', '', NULL, 1, 1, 0, '2026-03-06 10:11:54', NULL, NULL, NULL, NULL, NULL, NULL, 'assets/images/dealer_docs/dealer_63_69aaa99e52f34.jpg'),
(66, 'Mutale Lesa', 'mutalemattlesa@gmail.com', NULL, '', 'dealer', NULL, NULL, 1, 1, 0, '2026-03-07 10:32:40', NULL, NULL, '108104798742677225294', NULL, NULL, NULL, 'assets/images/dealer_docs/dealer_66_69b6868f59f85.jpg'),
(119, 'Vudo Chisala', 'chisalavudo@gmail.com', NULL, '', 'user', NULL, NULL, 1, 0, 0, '2026-03-21 17:48:49', NULL, NULL, '101673982545054802016', NULL, NULL, NULL, NULL);

--
-- Indexes for dumped tables
--

--
-- Indexes for table `activity_logs`
--
ALTER TABLE `activity_logs`
  ADD PRIMARY KEY (`id`),
  ADD KEY `user_id` (`user_id`);

--
-- Indexes for table `dealers`
--
ALTER TABLE `dealers`
  ADD PRIMARY KEY (`user_id`);

--
-- Indexes for table `leads`
--
ALTER TABLE `leads`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `notifications`
--
ALTER TABLE `notifications`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `notification_reads`
--
ALTER TABLE `notification_reads`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_read` (`notification_id`,`user_id`);

--
-- Indexes for table `properties`
--
ALTER TABLE `properties`
  ADD PRIMARY KEY (`id`),
  ADD KEY `dealer_id` (`dealer_id`);

--
-- Indexes for table `property_images`
--
ALTER TABLE `property_images`
  ADD PRIMARY KEY (`id`),
  ADD KEY `property_id` (`property_id`);

--
-- Indexes for table `property_reports`
--
ALTER TABLE `property_reports`
  ADD PRIMARY KEY (`id`),
  ADD KEY `property_id` (`property_id`);

--
-- Indexes for table `rentals`
--
ALTER TABLE `rentals`
  ADD PRIMARY KEY (`id`),
  ADD KEY `property_id` (`property_id`),
  ADD KEY `dealer_id` (`dealer_id`),
  ADD KEY `tenant_id` (`tenant_id`);

--
-- Indexes for table `rent_payments`
--
ALTER TABLE `rent_payments`
  ADD PRIMARY KEY (`id`),
  ADD KEY `rental_id` (`rental_id`),
  ADD KEY `tenant_id` (`tenant_id`);

--
-- Indexes for table `reports`
--
ALTER TABLE `reports`
  ADD PRIMARY KEY (`id`),
  ADD KEY `property_id` (`property_id`),
  ADD KEY `user_id` (`user_id`);

--
-- Indexes for table `saved_properties`
--
ALTER TABLE `saved_properties`
  ADD PRIMARY KEY (`id`),
  ADD KEY `user_id` (`user_id`),
  ADD KEY `property_id` (`property_id`);

--
-- Indexes for table `settings`
--
ALTER TABLE `settings`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `setting_key` (`setting_key`);

--
-- Indexes for table `subscriptions`
--
ALTER TABLE `subscriptions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `dealer_id` (`dealer_id`);

--
-- Indexes for table `tenancy_history`
--
ALTER TABLE `tenancy_history`
  ADD PRIMARY KEY (`id`),
  ADD KEY `property_id` (`property_id`);

--
-- Indexes for table `transactions`
--
ALTER TABLE `transactions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `user_id` (`user_id`);

--
-- Indexes for table `users`
--
ALTER TABLE `users`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `email` (`email`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `activity_logs`
--
ALTER TABLE `activity_logs`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=461;

--
-- AUTO_INCREMENT for table `leads`
--
ALTER TABLE `leads`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=11;

--
-- AUTO_INCREMENT for table `notifications`
--
ALTER TABLE `notifications`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

--
-- AUTO_INCREMENT for table `notification_reads`
--
ALTER TABLE `notification_reads`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT for table `properties`
--
ALTER TABLE `properties`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=16;

--
-- AUTO_INCREMENT for table `property_images`
--
ALTER TABLE `property_images`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=31;

--
-- AUTO_INCREMENT for table `property_reports`
--
ALTER TABLE `property_reports`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT for table `rentals`
--
ALTER TABLE `rentals`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=8;

--
-- AUTO_INCREMENT for table `rent_payments`
--
ALTER TABLE `rent_payments`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=9;

--
-- AUTO_INCREMENT for table `reports`
--
ALTER TABLE `reports`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `saved_properties`
--
ALTER TABLE `saved_properties`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT for table `settings`
--
ALTER TABLE `settings`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=13;

--
-- AUTO_INCREMENT for table `subscriptions`
--
ALTER TABLE `subscriptions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `tenancy_history`
--
ALTER TABLE `tenancy_history`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `transactions`
--
ALTER TABLE `transactions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

--
-- AUTO_INCREMENT for table `users`
--
ALTER TABLE `users`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=120;

--
-- Constraints for dumped tables
--

--
-- Constraints for table `activity_logs`
--
ALTER TABLE `activity_logs`
  ADD CONSTRAINT `activity_logs_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL;

--
-- Constraints for table `dealers`
--
ALTER TABLE `dealers`
  ADD CONSTRAINT `dealers_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `properties`
--
ALTER TABLE `properties`
  ADD CONSTRAINT `properties_ibfk_1` FOREIGN KEY (`dealer_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `property_images`
--
ALTER TABLE `property_images`
  ADD CONSTRAINT `property_images_ibfk_1` FOREIGN KEY (`property_id`) REFERENCES `properties` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `property_reports`
--
ALTER TABLE `property_reports`
  ADD CONSTRAINT `property_reports_ibfk_1` FOREIGN KEY (`property_id`) REFERENCES `properties` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `rentals`
--
ALTER TABLE `rentals`
  ADD CONSTRAINT `rentals_ibfk_1` FOREIGN KEY (`property_id`) REFERENCES `properties` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `rentals_ibfk_2` FOREIGN KEY (`dealer_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `rentals_ibfk_3` FOREIGN KEY (`tenant_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `rent_payments`
--
ALTER TABLE `rent_payments`
  ADD CONSTRAINT `rent_payments_ibfk_1` FOREIGN KEY (`rental_id`) REFERENCES `rentals` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `rent_payments_ibfk_2` FOREIGN KEY (`tenant_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `reports`
--
ALTER TABLE `reports`
  ADD CONSTRAINT `reports_ibfk_1` FOREIGN KEY (`property_id`) REFERENCES `properties` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `reports_ibfk_2` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL;

--
-- Constraints for table `saved_properties`
--
ALTER TABLE `saved_properties`
  ADD CONSTRAINT `saved_properties_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `saved_properties_ibfk_2` FOREIGN KEY (`property_id`) REFERENCES `properties` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `subscriptions`
--
ALTER TABLE `subscriptions`
  ADD CONSTRAINT `subscriptions_ibfk_1` FOREIGN KEY (`dealer_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `tenancy_history`
--
ALTER TABLE `tenancy_history`
  ADD CONSTRAINT `tenancy_history_ibfk_1` FOREIGN KEY (`property_id`) REFERENCES `properties` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `transactions`
--
ALTER TABLE `transactions`
  ADD CONSTRAINT `transactions_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
